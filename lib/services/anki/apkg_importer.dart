import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/html_markup.dart';
import 'package:knowit/services/media_service.dart';
import 'package:knowit/services/note_service.dart';
import 'package:knowit/services/sync/tombstone_store.dart';
import 'package:knowit/utils/id_generator.dart';
import 'package:knowit/utils/import_progress.dart';
import 'package:sqlite3/sqlite3.dart';

class AnkiFormatException implements Exception {
  final String message;

  const AnkiFormatException(this.message);

  @override
  String toString() => message;
}

class AnkiNoteDraft {
  final String frontText;
  final String backText;
  final CardType type;
  final List<String> tags;
  final String deckPath;
  final String? imageReference;
  final String? audioReference;

  const AnkiNoteDraft({
    required this.frontText,
    required this.backText,
    required this.type,
    required this.tags,
    required this.deckPath,
    this.imageReference,
    this.audioReference,
  });

  int get generatedCards =>
      const NoteService().specsFor(type, frontText).length;
}

class AnkiImportPreview {
  final String sourceName;
  final List<AnkiNoteDraft> notes;
  final Map<String, int> deckCardCounts;
  final Map<String, Uint8List> media;
  final List<String> warnings;
  final int ankiCardCount;

  const AnkiImportPreview({
    required this.sourceName,
    required this.notes,
    required this.deckCardCounts,
    required this.media,
    required this.warnings,
    required this.ankiCardCount,
  });

  int get generatedCardCount =>
      notes.fold<int>(0, (sum, note) => sum + note.generatedCards);

  int get noteCount => notes.length;
  int get mediaCount => media.length;
  List<String> get deckNames => deckCardCounts.keys.toList();
}

class AnkiImportResult {
  final int importedNotes;
  final int importedCards;
  final int skippedDuplicates;
  final int mediaFiles;
  final List<String> warnings;

  const AnkiImportResult({
    required this.importedNotes,
    required this.importedCards,
    required this.skippedDuplicates,
    required this.mediaFiles,
    required this.warnings,
  });

  String get summary => AppLocalizations.current.ankiImportResultSummary(
    importedNotes,
    importedCards,
    skippedDuplicates,
  );
}

/// Reads classic Anki `.apkg` packages (SQLite schema 11, collection.anki2 /
/// collection.anki21). Newer zstd-compressed collection.anki21b packages are
/// detected and rejected with a clear explanation rather than mis-read.
///
/// Scheduling history is deliberately not converted: Anki SM-2 state cannot be
/// mapped to FSRS without inventing values, so imported cards start as new and
/// the preview says so explicitly.
class AnkiImportService {
  static const int maxPackageBytes = 250 * 1024 * 1024;
  static const int maxUncompressedBytes = 500 * 1024 * 1024;
  static const int maxArchiveEntries = 20000;
  static const int maxNotes = 20000;
  static const int maxCards = 50000;

  const AnkiImportService();

  Future<({Uint8List bytes, String fileName})?> pickPackage() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: AppLocalizations.current.bi(
          'Choose an Anki package',
          'Выберите пакет Anki',
        ),
        type: FileType.custom,
        allowedExtensions: const ['apkg'],
      );
      if (files.isEmpty) return null;
      final file = files.first;
      return (bytes: await file.readAsBytes(), fileName: file.name);
    } on Object catch (error) {
      throw AnkiFormatException(
        AppLocalizations.current.bi(
          'Could not open that package: $error',
          'Не удалось открыть пакет: $error',
        ),
      );
    }
  }

  Future<AnkiImportPreview> previewBytes(
    Uint8List bytes, {
    String fileName = 'Anki package.apkg',
    void Function(ImportProgress progress)? onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    final throttler = ProgressThrottler(onProgress: onProgress);

    if (bytes.isEmpty) {
      throw AnkiFormatException(
        AppLocalizations.current.bi(
          'The selected package is empty.',
          'Выбранный пакет пуст.',
        ),
      );
    }
    if (bytes.length > maxPackageBytes) {
      throw AnkiFormatException(
        AppLocalizations.current.bi(
          'That package is too large (limit 250 MB).',
          'Пакет слишком большой (лимит 250 МБ).',
        ),
      );
    }

    cancellationToken?.throwIfCancelled();

    if (!kIsWeb) {
      return _previewBytesInIsolate(
        bytes: bytes,
        fileName: fileName,
        throttler: throttler,
        cancellationToken: cancellationToken,
      );
    } else {
      return _previewBytesDirect(
        bytes: bytes,
        fileName: fileName,
        throttler: throttler,
        cancellationToken: cancellationToken,
      );
    }
  }

  Future<AnkiImportPreview> _previewBytesInIsolate({
    required Uint8List bytes,
    required String fileName,
    required ProgressThrottler throttler,
    ImportCancellationToken? cancellationToken,
  }) async {
    final receivePort = ReceivePort();
    Isolate? isolate;
    final completer = Completer<AnkiImportPreview>();
    final localeCode = AppLocalizations.current.isRussian ? 'ru' : 'en';

    void cleanup() {
      try {
        receivePort.close();
      } catch (_) {}
      try {
        isolate?.kill(priority: Isolate.immediate);
      } catch (_) {}
    }

    receivePort.listen((message) {
      if (message is Map) {
        final type = message['type'] as String?;
        if (type == 'progress') {
          throttler.report(
            message['fraction'] as double?,
            message['stage'] as String,
            message['detail'] as String?,
          );
        } else if (type == 'success') {
          cleanup();
          if (!completer.isCompleted) {
            completer.complete(message['preview'] as AnkiImportPreview);
          }
        } else if (type == 'error') {
          cleanup();
          if (!completer.isCompleted) {
            final msg = message['message'] as String;
            final isFormat = message['isFormat'] as bool? ?? false;
            completer.completeError(
              isFormat ? AnkiFormatException(msg) : Exception(msg),
            );
          }
        }
      }
    });

    try {
      isolate = await Isolate.spawn<_ApkgIsolateParam>(
        _apkgIsolateWorker,
        _ApkgIsolateParam(
          bytes: bytes,
          fileName: fileName,
          sendPort: receivePort.sendPort,
          localeCode: localeCode,
        ),
      );
    } catch (_) {
      cleanup();
      return _previewBytesDirect(
        bytes: bytes,
        fileName: fileName,
        throttler: throttler,
        cancellationToken: cancellationToken,
      );
    }

    while (!completer.isCompleted) {
      if (cancellationToken?.isCancelled == true) {
        cleanup();
        throw const ImportCancelledException();
      }
      await Future.any([
        completer.future,
        Future<void>.delayed(const Duration(milliseconds: 40)),
      ]);
    }

    return completer.future;
  }

  static void _apkgIsolateWorker(_ApkgIsolateParam param) {
    AppLocalizations.useLocale(Locale(param.localeCode));
    void report(double? fraction, String stage, [String? detail]) {
      param.sendPort.send({
        'type': 'progress',
        'fraction': fraction,
        'stage': stage,
        'detail': detail,
      });
    }

    try {
      report(0.08, 'Validating package archive…');
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(param.bytes, verify: true);
      } on Object catch (error) {
        throw AnkiFormatException(
          AppLocalizations.current.bi(
            'This is not a readable .apkg archive. It may be corrupted or encrypted. '
                '($error)',
            'Это не читаемый архив .apkg. Возможно, он повреждён или зашифрован. '
                '($error)',
          ),
        );
      }

      if (archive.files.length > maxArchiveEntries) {
        throw AnkiFormatException(
          AppLocalizations.current.bi(
            'The package contains too many files to import safely.',
            'Пакет содержит слишком много файлов для безопасного импорта.',
          ),
        );
      }
      var uncompressed = 0;
      for (final file in archive.files) {
        uncompressed += file.size;
        if (uncompressed > maxUncompressedBytes) {
          throw AnkiFormatException(
            AppLocalizations.current.bi(
              'The expanded package is too large to import safely.',
              'Распакованный пакет слишком большой для безопасного импорта.',
            ),
          );
        }
      }

      report(0.25, 'Extracting database…');
      final dbFile = _findDatabaseInArchive(archive);
      if (dbFile == null) {
        if (archive.files.any((file) => file.name == 'collection.anki21b')) {
          throw AnkiFormatException(
            AppLocalizations.current.bi(
              'This Anki package uses the newer zstd-compressed collection.anki21b '
                  'format, which is not supported yet. Export it from Anki with '
                  '"Support older Anki versions" enabled to import it here.',
              'Этот пакет Anki использует новый формат collection.anki21b со сжатием '
                  'zstd, который пока не поддерживается. Экспортируйте его из Anki, '
                  'включив «Поддержку старых версий Anki».',
            ),
          );
        }
        throw AnkiFormatException(
          AppLocalizations.current.bi(
            'The package does not contain a supported Anki collection database.',
            'Пакет не содержит поддерживаемой базы коллекции Anki.',
          ),
        );
      }

      report(0.35, 'Reading notes and decks…');
      final dbBytes = _bytesOfFile(dbFile);
      final parsed = _readDatabaseSync(dbBytes);
      final mediaMap = _readMediaManifestFromArchive(archive);
      final warnings = <String>[
        AppLocalizations.current.bi(
          'Anki scheduling history was not imported. Cards will start as new '
              'FSRS cards; existing decks and cards are kept.',
          'История планирования Anki не импортирована. Карточки начнут как новые '
              'в FSRS; существующие колоды и карточки сохранены.',
        ),
        ...parsed.warnings,
      ];

      report(0.55, 'Resolving media references…');
      final resolver = _MediaResolver(archive, mediaMap);
      final media = <String, Uint8List>{};
      final notes = <AnkiNoteDraft>[];
      final totalNotes = parsed.notes.length;

      for (var i = 0; i < totalNotes; i++) {
        if (i % 50 == 0) {
          final fraction =
              0.55 + 0.35 * (i / (totalNotes > 0 ? totalNotes : 1));
          report(fraction, 'Processing notes…', '($i / $totalNotes)');
        }

        final note = parsed.notes[i];
        var noteWarnings = 0;
        String? imageReference = note.imageReference != null
            ? _normalizeMediaRef(note.imageReference!)
            : null;
        String? audioReference = note.audioReference != null
            ? _normalizeMediaRef(note.audioReference!)
            : null;

        if (imageReference != null) {
          final found = resolver.resolve(imageReference);
          if (found != null) {
            media[imageReference] = found;
          } else {
            warnings.add(
              AppLocalizations.current.bi(
                'Missing image "$imageReference" in one note.',
                'В одной заметке отсутствует изображение "$imageReference".',
              ),
            );
            imageReference = null;
            noteWarnings++;
          }
        }
        if (audioReference != null) {
          final found = resolver.resolve(audioReference);
          if (found != null) {
            media[audioReference] = found;
          } else {
            warnings.add(
              AppLocalizations.current.bi(
                'Missing audio "$audioReference" in one note.',
                'В одной заметке отсутствует аудио "$audioReference".',
              ),
            );
            audioReference = null;
            noteWarnings++;
          }
        }

        notes.add(
          AnkiNoteDraft(
            frontText: note.frontText,
            backText: note.backText,
            type: note.type,
            tags: note.tags,
            deckPath: note.deckPath,
            imageReference: imageReference,
            audioReference: audioReference,
          ),
        );
        if (noteWarnings > 0) continue;
      }

      if (notes.isEmpty) {
        throw AnkiFormatException(
          AppLocalizations.current.bi(
            'No importable cards were found in this Anki package.',
            'В этом пакете Anki не найдено карточек для импорта.',
          ),
        );
      }
      if (notes.length > maxNotes ||
          notes.fold<int>(0, (sum, note) => sum + note.generatedCards) >
              maxCards) {
        throw AnkiFormatException(
          AppLocalizations.current.bi(
            'This package is too large to import in one go.',
            'Этот пакет слишком большой для импорта за один раз.',
          ),
        );
      }

      final deckCounts = <String, int>{};
      for (final note in notes) {
        deckCounts[note.deckPath] =
            (deckCounts[note.deckPath] ?? 0) + note.generatedCards;
      }

      final preview = AnkiImportPreview(
        sourceName: param.fileName,
        notes: notes,
        deckCardCounts: deckCounts,
        media: media,
        warnings: _dedupe(warnings),
        ankiCardCount: parsed.cardCount,
      );

      report(1.0, 'Preview ready.');
      param.sendPort.send({'type': 'success', 'preview': preview});
    } on AnkiFormatException catch (e) {
      param.sendPort.send({
        'type': 'error',
        'message': e.message,
        'isFormat': true,
      });
    } catch (e) {
      param.sendPort.send({
        'type': 'error',
        'message': e.toString(),
        'isFormat': false,
      });
    }
  }

  Future<AnkiImportPreview> _previewBytesDirect({
    required Uint8List bytes,
    required String fileName,
    required ProgressThrottler throttler,
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    throttler.report(0.08, 'Validating package archive…');
    await Future<void>.delayed(Duration.zero);

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } on Object catch (error) {
      throw AnkiFormatException(
        AppLocalizations.current.bi(
          'This is not a readable .apkg archive. It may be corrupted or encrypted. '
              '($error)',
          'Это не читаемый архив .apkg. Возможно, он повреждён или зашифрован. '
              '($error)',
        ),
      );
    }
    if (archive.files.length > maxArchiveEntries) {
      throw AnkiFormatException(
        AppLocalizations.current.bi(
          'The package contains too many files to import safely.',
          'Пакет содержит слишком много файлов для безопасного импорта.',
        ),
      );
    }
    var uncompressed = 0;
    for (final file in archive.files) {
      uncompressed += file.size;
      if (uncompressed > maxUncompressedBytes) {
        throw AnkiFormatException(
          AppLocalizations.current.bi(
            'The expanded package is too large to import safely.',
            'Распакованный пакет слишком большой для безопасного импорта.',
          ),
        );
      }
    }

    cancellationToken?.throwIfCancelled();
    throttler.report(0.25, 'Extracting database…');
    await Future<void>.delayed(Duration.zero);

    final dbFile = _findDatabaseInArchive(archive);
    if (dbFile == null) {
      if (archive.files.any((file) => file.name == 'collection.anki21b')) {
        throw AnkiFormatException(
          AppLocalizations.current.bi(
            'This Anki package uses the newer zstd-compressed collection.anki21b '
                'format, which is not supported yet. Export it from Anki with '
                '"Support older Anki versions" enabled to import it here.',
            'Этот пакет Anki использует новый формат collection.anki21b со сжатием '
                'zstd, который пока не поддерживается. Экспортируйте его из Anki, '
                'включив «Поддержку старых версий Anki».',
          ),
        );
      }
      throw AnkiFormatException(
        AppLocalizations.current.bi(
          'The package does not contain a supported Anki collection database.',
          'Пакет не содержит поддерживаемой базы коллекции Anki.',
        ),
      );
    }

    cancellationToken?.throwIfCancelled();
    throttler.report(0.35, 'Reading notes and decks…');
    await Future<void>.delayed(Duration.zero);

    final dbBytes = _bytesOfFile(dbFile);
    final parsed = _readDatabaseSync(dbBytes);
    final mediaMap = _readMediaManifestFromArchive(archive);
    final warnings = <String>[
      AppLocalizations.current.bi(
        'Anki scheduling history was not imported. Cards will start as new '
            'FSRS cards; existing decks and cards are kept.',
        'История планирования Anki не импортирована. Карточки начнут как новые '
            'в FSRS; существующие колоды и карточки сохранены.',
      ),
      ...parsed.warnings,
    ];

    cancellationToken?.throwIfCancelled();
    throttler.report(0.55, 'Resolving media references…');
    await Future<void>.delayed(Duration.zero);

    final resolver = _MediaResolver(archive, mediaMap);
    final media = <String, Uint8List>{};
    final notes = <AnkiNoteDraft>[];
    final totalNotes = parsed.notes.length;

    for (var i = 0; i < totalNotes; i++) {
      if (i % 50 == 0) {
        cancellationToken?.throwIfCancelled();
        final fraction = 0.55 + 0.35 * (i / (totalNotes > 0 ? totalNotes : 1));
        throttler.report(fraction, 'Processing notes…', '($i / $totalNotes)');
        await Future<void>.delayed(Duration.zero);
      }

      final note = parsed.notes[i];
      var noteWarnings = 0;
      String? imageReference = note.imageReference != null
          ? _normalizeMediaRef(note.imageReference!)
          : null;
      String? audioReference = note.audioReference != null
          ? _normalizeMediaRef(note.audioReference!)
          : null;

      if (imageReference != null) {
        final found = resolver.resolve(imageReference);
        if (found != null) {
          media[imageReference] = found;
        } else {
          warnings.add(
            AppLocalizations.current.bi(
              'Missing image "$imageReference" in one note.',
              'В одной заметке отсутствует изображение "$imageReference".',
            ),
          );
          imageReference = null;
          noteWarnings++;
        }
      }
      if (audioReference != null) {
        final found = resolver.resolve(audioReference);
        if (found != null) {
          media[audioReference] = found;
        } else {
          warnings.add(
            AppLocalizations.current.bi(
              'Missing audio "$audioReference" in one note.',
              'В одной заметке отсутствует аудио "$audioReference".',
            ),
          );
          audioReference = null;
          noteWarnings++;
        }
      }

      notes.add(
        AnkiNoteDraft(
          frontText: note.frontText,
          backText: note.backText,
          type: note.type,
          tags: note.tags,
          deckPath: note.deckPath,
          imageReference: imageReference,
          audioReference: audioReference,
        ),
      );
      if (noteWarnings > 0) continue;
    }

    if (notes.isEmpty) {
      throw AnkiFormatException(
        AppLocalizations.current.bi(
          'No importable cards were found in this Anki package.',
          'В этом пакете Anki не найдено карточек для импорта.',
        ),
      );
    }
    if (notes.length > maxNotes ||
        notes.fold<int>(0, (sum, note) => sum + note.generatedCards) >
            maxCards) {
      throw AnkiFormatException(
        AppLocalizations.current.bi(
          'This package is too large to import in one go.',
          'Этот пакет слишком большой для импорта за один раз.',
        ),
      );
    }

    final deckCounts = <String, int>{};
    for (final note in notes) {
      deckCounts[note.deckPath] =
          (deckCounts[note.deckPath] ?? 0) + note.generatedCards;
    }

    throttler.flush(1.0, 'Preview ready.');

    return AnkiImportPreview(
      sourceName: fileName,
      notes: notes,
      deckCardCounts: deckCounts,
      media: media,
      warnings: _dedupe(warnings),
      ankiCardCount: parsed.cardCount,
    );
  }

  static ArchiveFile? _findDatabaseInArchive(Archive archive) {
    for (final name in ['collection.anki21', 'collection.anki2']) {
      for (final file in archive.files) {
        if (file.name == name && file.isFile) return file;
      }
    }
    return null;
  }

  static Uint8List _bytesOfFile(ArchiveFile file) => file.content;

  static _ParsedAnki _readDatabaseSync(Uint8List bytes) {
    Directory? temp;
    File? file;
    Database? db;
    try {
      temp = Directory.systemTemp.createTempSync('knowit_apkg_');
      file = File('${temp.path}/collection.db');
      file.writeAsBytesSync(bytes, flush: false);
      db = sqlite3.open(file.path);

      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((row) => row['name'].toString())
          .toSet();
      if (!tables.containsAll({'col', 'notes', 'cards'})) {
        throw const AnkiFormatException(
          'The package database is missing Anki note or card tables.',
        );
      }

      final colRows = db.select('SELECT decks, models FROM col LIMIT 1');
      if (colRows.isEmpty) {
        throw const AnkiFormatException(
          'The Anki collection is empty or missing its metadata.',
        );
      }
      final decksJson = jsonDecode(colRows.first['decks'].toString());
      final modelsJson = jsonDecode(colRows.first['models'].toString());
      if (decksJson is! Map || modelsJson is! Map) {
        throw const AnkiFormatException(
          'The Anki collection metadata is malformed.',
        );
      }
      final decks = <String, String>{};
      for (final entry in decksJson.entries) {
        final value = entry.value;
        if (value is Map && value['name'] is String) {
          decks[entry.key.toString()] = value['name'] as String;
        }
      }

      final noteRows = db.select(
        'SELECT id, mid, tags, flds FROM notes ORDER BY id',
      );
      final cardRows = db.select(
        'SELECT nid, did, ord FROM cards ORDER BY nid, ord',
      );
      final cardsByNote = <String, List<Map<String, Object?>>>{};
      for (final row in cardRows) {
        final nid = row['nid'].toString();
        cardsByNote.putIfAbsent(nid, () => []).add(row);
      }

      final warnings = <String>[];
      final notes = <_AnkiNoteData>[];
      for (final row in noteRows) {
        final nid = row['id'].toString();
        final mid = row['mid'].toString();
        final cards = cardsByNote[nid];
        if (cards == null || cards.isEmpty) continue;
        final model = modelsJson[mid];
        if (model is! Map) {
          warnings.add('Skipped a note whose Anki note type is missing.');
          continue;
        }
        final modelType = (model['type'] as num?)?.toInt() ?? 0;
        final fields = row['flds'].toString().split('\x1f');
        final tags = (row['tags']?.toString() ?? '')
            .trim()
            .split(RegExp(r'\s+'))
            .where((tag) => tag.isNotEmpty)
            .toList();
        final rawText = fields.join('\n');
        final mediaReferences = extractMediaReferences(rawText);
        final imageReference = _pickImageReference(mediaReferences);
        final audioReference = _pickAudioReference(mediaReferences);
        if (mediaReferences.where(_looksLikeImage).length > 1 ||
            mediaReferences.where(_looksLikeAudio).length > 1) {
          warnings.add(
            'A note references multiple media files; only the first image or '
            'audio was attached because KnowIt cards support one of each.',
          );
        }
        final deckId = cards.first['did'].toString();
        final deckPath = decks[deckId] ?? 'Imported from Anki';
        if (cards.map((card) => card['did'].toString()).toSet().length > 1) {
          warnings.add(
            'A note had cards in more than one deck; the first deck was used.',
          );
        }
        final ords =
            cards
                .map((card) => (card['ord'] as num?)?.toInt() ?? 0)
                .toSet()
                .toList()
              ..sort();

        if (modelType == 1) {
          var front = htmlToMarkup(fields.isNotEmpty ? fields.first : '');
          var back = htmlToMarkup(fields.skip(1).join('\n\n'));
          if (front.trim().isEmpty && audioReference != null) {
            front = '[Audio]';
          }
          if (back.trim().isEmpty && audioReference != null) {
            back = '[Audio]';
          }
          if (!RegExp(r'\{\{c\d+::.+?\}\}').hasMatch(front)) {
            warnings.add(
              'Skipped a cloze note without valid {{c1::…}} deletions.',
            );
            continue;
          }
          notes.add(
            _AnkiNoteData(
              frontText: front,
              backText: back,
              type: CardType.cloze,
              tags: tags,
              deckPath: deckPath,
              imageReference: imageReference,
              audioReference: audioReference,
            ),
          );
        } else {
          if (ords.any((ord) => ord > 1)) {
            warnings.add(
              'Skipped custom card templates beyond the first two directions '
              'on one note.',
            );
          }
          final supported = ords.where((ord) => ord <= 1).toList();
          if (supported.isEmpty) continue;
          var front = htmlToMarkup(fields.isNotEmpty ? fields.first : '');
          var back = htmlToMarkup(fields.skip(1).join('\n\n'));

          // If note contains audio/image and one side is text-empty, retain card with prompt
          if (front.trim().isEmpty && (audioReference != null || imageReference != null)) {
            front = audioReference != null ? '[Audio]' : '[Image]';
          }
          if (back.trim().isEmpty && (audioReference != null || imageReference != null)) {
            back = audioReference != null ? '[Audio]' : '[Image]';
          }

          if (front.trim().isEmpty || back.trim().isEmpty) {
            warnings.add('Skipped an Anki note with an empty field.');
            continue;
          }
          notes.add(
            _AnkiNoteData(
              frontText: front,
              backText: back,
              type: supported.contains(1) ? CardType.reversed : CardType.basic,
              tags: tags,
              deckPath: deckPath,
              imageReference: imageReference,
              audioReference: audioReference,
            ),
          );
        }
      }

      return _ParsedAnki(
        notes: notes,
        warnings: warnings,
        cardCount: cardRows.length,
      );
    } on AnkiFormatException {
      rethrow;
    } on Object catch (error) {
      throw AnkiFormatException(
        'The Anki database could not be read. The package may be corrupted or '
        'from an unsupported Anki version. ($error)',
      );
    } finally {
      try {
        db?.close();
      } catch (_) {}
      try {
        if (file != null && file.existsSync()) file.deleteSync();
        if (temp != null && temp.existsSync()) temp.deleteSync(recursive: true);
      } on Object {
        // Temporary cleanup must not mask the import result.
      }
    }
  }

  static Map<String, String> _readMediaManifestFromArchive(Archive archive) {
    ArchiveFile? manifest;
    for (final file in archive.files) {
      if (file.name == 'media' && file.isFile) {
        manifest = file;
        break;
      }
    }
    if (manifest == null) return const {};
    try {
      final decoded = jsonDecode(
        utf8.decode(_bytesOfFile(manifest), allowMalformed: true),
      );
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value.toString(),
      };
    } on Object {
      return const {};
    }
  }

  static String _normalizeMediaRef(String ref) {
    var cleaned = ref.trim();
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    try {
      if (cleaned.contains('%')) {
        cleaned = Uri.decodeFull(cleaned);
      }
    } on Object {
      // Best-effort URI decode.
    }
    final queryIndex = cleaned.indexOf('?');
    if (queryIndex > 0) {
      cleaned = cleaned.substring(0, queryIndex);
    }
    return cleaned.split(RegExp(r'[/\\]')).last.trim();
  }

  /// Imports the preview. Media and cards are written in batches; failures roll
  /// back records created by this import atomically.
  Future<AnkiImportResult> commit(
    AnkiImportPreview preview, {
    bool skipDuplicates = true,
    void Function(ImportProgress progress)? onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    final throttler = ProgressThrottler(onProgress: onProgress);

    cancellationToken?.throwIfCancelled();
    throttler.report(0.05, 'Preparing deck hierarchy…');

    await HiveService.ensureReady();
    final createdCardIds = <String>[];
    final createdDeckIds = <String>[];
    final mediaPaths = <String>[];
    final warnings = <String>[];
    var skipped = 0;

    final deckByPath = <String, Collection>{};
    final existing = HiveService.getAllCollections();
    final byParentAndName = <String, Collection>{
      for (final deck in existing)
        '${deck.parentId ?? ''}|${deck.name.toLowerCase()}': deck,
    };
    final existingDeckPaths = {
      for (final deck in existing) deck.id: _appDeckPath(existing, deck),
    };

    Collection ensureDeck(String path) {
      if (deckByPath.containsKey(path)) return deckByPath[path]!;
      final parts = path.split('::').where((part) => part.trim().isNotEmpty);
      String? parentId;
      var currentPath = '';
      Collection? result;
      for (final rawPart in parts) {
        final name = rawPart.trim();
        currentPath = currentPath.isEmpty ? name : '$currentPath::$name';
        final key = '${parentId ?? ''}|${name.toLowerCase()}';
        var deck = byParentAndName[key];
        if (deck == null) {
          deck = Collection(
            id: newId(),
            name: name,
            emoji: '',
            colorValue: 0xFFFFC107,
            parentId: parentId,
            description: 'Imported from Anki',
            sortOrder: existing.length + createdDeckIds.length,
          );
          createdDeckIds.add(deck.id);
          byParentAndName[key] = deck;
        }
        parentId = deck.id;
        result = deck;
      }
      final finalDeck = result ?? existing.first;
      deckByPath[path] = finalDeck;
      return finalDeck;
    }

    cancellationToken?.throwIfCancelled();
    throttler.report(0.12, 'Checking duplicates…');

    // Create/reuse the collection hierarchy before writing cards.
    final existingKeys = <String>{};
    if (skipDuplicates) {
      for (final card in HiveService.getAllCards()) {
        final path = existingDeckPaths[card.collectionId] ?? '';
        existingKeys.add('$path|${_duplicateKey(card)}');
      }
    }
    final notesToImport = <AnkiNoteDraft>[];
    for (final note in preview.notes) {
      final key = '${note.deckPath}|${_noteDuplicateKey(note)}';
      if (skipDuplicates && !existingKeys.add(key)) {
        skipped++;
        continue;
      }
      notesToImport.add(note);
    }

    for (final note in notesToImport) {
      ensureDeck(note.deckPath);
    }

    final storedMediaMap = <String, String>{};

    try {
      cancellationToken?.throwIfCancelled();
      throttler.report(0.20, 'Creating decks…');

      for (final deck in byParentAndName.values) {
        if (!createdDeckIds.contains(deck.id)) continue;
        await HiveService.createCollection(deck);
      }

      // Pre-store referenced media with deduplication to avoid redundant writes
      final referencedMedia = <String>{
        for (final note in notesToImport) ...[
          if (note.imageReference != null) note.imageReference!,
          if (note.audioReference != null) note.audioReference!,
        ],
      }.toList();

      final totalMedia = referencedMedia.length;
      for (var m = 0; m < totalMedia; m++) {
        if (m % 5 == 0) {
          cancellationToken?.throwIfCancelled();
          final frac = 0.20 + 0.30 * (m / (totalMedia > 0 ? totalMedia : 1));
          throttler.report(
            frac,
            'Extracting media files…',
            '(${m + 1} / $totalMedia)',
          );
          await Future<void>.delayed(Duration.zero);
        }
        final ref = referencedMedia[m];
        final bytes = preview.media[ref];
        if (bytes != null) {
          final stored = await MediaService.storeBytes(
            bytes: bytes,
            fileName: ref,
          );
          if (stored != null) {
            storedMediaMap[ref] = stored;
            if (!mediaPaths.contains(stored)) {
              mediaPaths.add(stored);
            }
          } else {
            warnings.add('Media storage is unavailable; $ref was not attached.');
          }
        }
      }

      // Pre-plan all cards in memory
      final noteService = const NoteService();
      final cardsToWrite = <CardItem>[];
      final totalNotes = notesToImport.length;

      for (var n = 0; n < totalNotes; n++) {
        if (n % 50 == 0) {
          cancellationToken?.throwIfCancelled();
          final frac = 0.50 + 0.35 * (n / (totalNotes > 0 ? totalNotes : 1));
          throttler.report(frac, 'Planning cards…', '(${n + 1} / $totalNotes)');
          await Future<void>.delayed(Duration.zero);
        }
        final note = notesToImport[n];
        final deck = deckByPath[note.deckPath]!;
        final imagePath = note.imageReference != null
            ? storedMediaMap[note.imageReference]
            : null;
        final audioPath = note.audioReference != null
            ? storedMediaMap[note.audioReference]
            : null;

        final edited = CardItem(
          id: newId(),
          frontText: note.frontText,
          backText: note.backText,
          collectionId: deck.id,
          type: note.type,
          tags: note.tags,
          imagePath: imagePath,
          audioPath: audioPath,
        );
        final plan = noteService.plan(
          edited: edited,
          existing: const [],
          isNewNote: true,
        );
        cardsToWrite.addAll(plan.cards);
        createdCardIds.addAll(plan.cards.map((card) => card.id));
      }

      // Batch write cards in chunks of 250 with UI yielding
      const chunkSize = 250;
      final totalCards = cardsToWrite.length;
      for (var c = 0; c < totalCards; c += chunkSize) {
        cancellationToken?.throwIfCancelled();
        final end = (c + chunkSize < totalCards) ? c + chunkSize : totalCards;
        final chunk = cardsToWrite.sublist(c, end);
        await HiveService.saveCards(chunk);
        final frac = 0.85 + 0.12 * (end / (totalCards > 0 ? totalCards : 1));
        throttler.report(
          frac,
          'Saving cards to database…',
          '($end / $totalCards)',
        );
        await Future<void>.delayed(Duration.zero);
      }
    } on Object catch (error) {
      // Roll back only what this import created.
      await HiveService.deleteCards(createdCardIds);
      for (final cardId in createdCardIds) {
        await TombstoneStore.remove(SyncEntityType.card, cardId);
      }
      for (final deckId in createdDeckIds) {
        await HiveService.deleteCollectionCascade(deckId);
        await TombstoneStore.remove(SyncEntityType.collection, deckId);
      }
      for (final path in mediaPaths) {
        await MediaService.deleteManaged(path);
      }
      if (error is ImportCancelledException) {
        rethrow;
      }
      throw AnkiFormatException(
        'The import failed and was rolled back. No existing data was changed. '
        '($error)',
      );
    }

    throttler.flush(0.98, 'Finalizing import…');
    await HiveService.refreshCardCounts();
    throttler.flush(1.0, 'Import completed successfully.');

    return AnkiImportResult(
      importedNotes: preview.notes.length - skipped,
      importedCards: createdCardIds.length,
      skippedDuplicates: skipped,
      mediaFiles: mediaPaths.length,
      warnings: _dedupe([...warnings, ...preview.warnings]),
    );
  }

  String _duplicateKey(CardItem card) {
    final front = normalizeForDuplicate(card.frontText);
    final back = normalizeForDuplicate(card.backText);
    if (card.isCloze) return 'c:$front';
    final a = '$front|$back';
    final b = '$back|$front';
    return a.compareTo(b) <= 0 ? 's:$a' : 's:$b';
  }

  String _noteDuplicateKey(AnkiNoteDraft note) {
    final front = normalizeForDuplicate(note.frontText);
    final back = normalizeForDuplicate(note.backText);
    if (note.type == CardType.cloze) return 'c:$front';
    final a = '$front|$back';
    final b = '$back|$front';
    return a.compareTo(b) <= 0 ? 's:$a' : 's:$b';
  }

  String _appDeckPath(List<Collection> collections, Collection deck) {
    final byId = {for (final item in collections) item.id: item};
    final parts = <String>[deck.name];
    var parentId = deck.parentId;
    var guard = 0;
    while (parentId != null && parentId.isNotEmpty && guard < 32) {
      final parent = byId[parentId];
      if (parent == null) break;
      parts.insert(0, parent.name);
      parentId = parent.parentId;
      guard++;
    }
    return parts.join('::');
  }

  static List<String> _dedupe(List<String> values) => values.toSet().toList();
}

class _ApkgIsolateParam {
  final Uint8List bytes;
  final String fileName;
  final SendPort sendPort;
  final String localeCode;

  _ApkgIsolateParam({
    required this.bytes,
    required this.fileName,
    required this.sendPort,
    required this.localeCode,
  });
}

class _MediaResolver {
  final Map<String, ArchiveFile> filesByName = {};
  final Map<String, ArchiveFile> filesByLowerName = {};
  final Map<String, String> manifestByVal = {};
  final Map<String, String> manifestByLowerVal = {};

  _MediaResolver(Archive archive, Map<String, String> manifest) {
    for (final file in archive.files) {
      if (file.isFile) {
        filesByName[file.name] = file;
        final clean = AnkiImportService._normalizeMediaRef(file.name);
        filesByName[clean] = file;
        filesByLowerName[clean.toLowerCase()] = file;
      }
    }
    for (final entry in manifest.entries) {
      manifestByVal[entry.value] = entry.key;
      final clean = AnkiImportService._normalizeMediaRef(entry.value);
      manifestByVal[clean] = entry.key;
      manifestByLowerVal[clean.toLowerCase()] = entry.key;
    }
  }

  Uint8List? resolve(String reference) {
    final normalizedRef = AnkiImportService._normalizeMediaRef(reference);
    final lowerRef = normalizedRef.toLowerCase();

    // 1. Manifest lookup
    final index = manifestByVal[reference] ??
        manifestByVal[normalizedRef] ??
        manifestByLowerVal[lowerRef];

    if (index != null) {
      final file = filesByName[index];
      if (file != null) {
        try {
          return file.content;
        } on Object {
          return null;
        }
      }
    }

    // 2. Direct zip entry fallback
    final direct = filesByName[normalizedRef] ?? filesByLowerName[lowerRef];
    if (direct != null) {
      try {
        return direct.content;
      } on Object {
        return null;
      }
    }

    return null;
  }
}

class _ParsedAnki {
  final List<_AnkiNoteData> notes;
  final List<String> warnings;
  final int cardCount;

  const _ParsedAnki({
    required this.notes,
    required this.warnings,
    required this.cardCount,
  });
}

class _AnkiNoteData {
  final String frontText;
  final String backText;
  final CardType type;
  final List<String> tags;
  final String deckPath;
  final String? imageReference;
  final String? audioReference;

  const _AnkiNoteData({
    required this.frontText,
    required this.backText,
    required this.type,
    required this.tags,
    required this.deckPath,
    this.imageReference,
    this.audioReference,
  });
}

bool _looksLikeImage(String ref) {
  final clean = AnkiImportService._normalizeMediaRef(ref);
  return RegExp(
    r'\.(png|jpe?g|gif|webp|bmp|svg)$',
    caseSensitive: false,
  ).hasMatch(clean);
}

bool _looksLikeAudio(String ref) {
  final clean = AnkiImportService._normalizeMediaRef(ref);
  return RegExp(
    r'\.(mp3|wav|m4a|ogg|aac|flac|opus)$',
    caseSensitive: false,
  ).hasMatch(clean);
}

String? _pickImageReference(Iterable<String> references) {
  for (final reference in references) {
    if (_looksLikeImage(reference) && !_looksLikeAudio(reference)) {
      return reference;
    }
  }
  return null;
}

String? _pickAudioReference(Iterable<String> references) {
  for (final reference in references) {
    if (_looksLikeAudio(reference)) return reference;
  }
  return null;
}
