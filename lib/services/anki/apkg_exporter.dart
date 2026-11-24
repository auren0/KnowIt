import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/html_markup.dart';
import 'package:knowit/services/note_service.dart';
import 'package:knowit/utils/formatters.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class AnkiExportException implements Exception {
  final String message;

  const AnkiExportException(this.message);

  @override
  String toString() => message;
}

class AnkiExportResult {
  final Uint8List bytes;
  final String fileName;
  final int notes;
  final int cards;
  final int media;
  final List<String> warnings;

  const AnkiExportResult({
    required this.bytes,
    required this.fileName,
    required this.notes,
    required this.cards,
    required this.media,
    this.warnings = const [],
  });

  String get summary =>
      AppLocalizations.current.ankiExportSummary(notes, cards, media);
}

/// Builds a classic `.apkg` (Anki schema 11) for cards in one collection or the
/// whole library.
///
/// KnowIt FSRS scheduling cannot be represented accurately in Anki's SM-2
/// fields, so exported cards are intentionally new and unscheduled. The UI
/// states this before export. No review history is exported.
class AnkiExportService {
  static const int _basicModelId = 1600000000001;
  static const int _reversedModelId = 1600000000002;
  static const int _clozeModelId = 1600000000003;
  static const String _css = '''
.card {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  font-size: 20px;
  text-align: left;
  color: #222;
  background: #fff;
}
.cloze { font-weight: bold; color: #2e6da4; }
''';

  const AnkiExportService();

  Future<AnkiExportResult> build({String? collectionId}) async {
    final cards = collectionId == null
        ? HiveService.getAllCards()
        : HiveService.getCardsByCollection(collectionId);
    if (cards.isEmpty) {
      throw AnkiExportException(
        AppLocalizations.current.bi(
          'There are no cards to export from this selection.',
          'В выбранном наборе нет карточек для экспорта.',
        ),
      );
    }
    final collections = HiveService.getAllCollections();
    final notes = <String, List<CardItem>>{};
    for (final card in cards) {
      notes.putIfAbsent(card.noteKey, () => []).add(card);
    }

    final deckIds = <String, int>{'Default': 1};
    final deckRows = <Map<String, dynamic>>[];
    var nextDeckId = 2;
    final usedDecks = <String, Collection>{};
    for (final card in cards) {
      final deck = HiveService.getCollection(card.collectionId);
      if (deck == null) continue;
      usedDecks[deck.id] = deck;
    }
    final usedDeckPaths = <String>{};
    for (final deck in usedDecks.values) {
      final path = _deckPath(collections, deck);
      final parts = path.split('::');
      var current = '';
      for (final part in parts) {
        current = current.isEmpty ? part : '$current::$part';
        if (current.trim().isNotEmpty) usedDeckPaths.add(current);
      }
    }
    for (final path in usedDeckPaths) {
      if (deckIds.containsKey(path)) continue;
      final id = nextDeckId++;
      deckIds[path] = id;
      deckRows.add(_deckJson(id, path));
    }
    deckRows.add(_deckJson(1, 'Default'));

    final models = {
      _basicModelId: _modelJson(
        id: _basicModelId,
        name: 'KnowIt Basic',
        type: 0,
        templates: [
          {
            'name': 'Card 1',
            'qfmt': '{{Front}}',
            'afmt': '{{FrontSide}}<hr id=answer>{{Back}}',
          },
        ],
        req: [
          [
            0,
            'all',
            [0],
          ],
        ],
      ),
      _reversedModelId: _modelJson(
        id: _reversedModelId,
        name: 'KnowIt Reversed',
        type: 0,
        templates: [
          {
            'name': 'Card 1',
            'qfmt': '{{Front}}',
            'afmt': '{{FrontSide}}<hr id=answer>{{Back}}',
          },
          {
            'name': 'Card 2',
            'qfmt': '{{Back}}',
            'afmt': '{{FrontSide}}<hr id=answer>{{Front}}',
          },
        ],
        req: [
          [
            0,
            'all',
            [0],
          ],
          [
            1,
            'all',
            [1],
          ],
        ],
      ),
      _clozeModelId: _modelJson(
        id: _clozeModelId,
        name: 'KnowIt Cloze',
        type: 1,
        templates: [
          {
            'name': 'Cloze',
            'qfmt': '{{cloze:Text}}',
            'afmt': '{{cloze:Text}}<br>{{Back Extra}}',
          },
        ],
        req: [
          [
            0,
            'any',
            [0],
          ],
        ],
      ),
    };

    final media = <String, Uint8List>{};
    final warnings = <String>[
      AppLocalizations.current.bi(
        'Scheduling was not exported. All cards will open in Anki as new cards; '
            'FSRS stability and review history are not part of the APKG format.',
        'Планирование не экспортировано. Все карточки откроются в Anki как новые; '
            'стабильность FSRS и история повторений не входят в формат APKG.',
      ),
    ];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final nowSeconds = nowMs ~/ 1000;

    Directory? temp;
    File? dbFile;
    Database? db;
    try {
      Directory root;
      try {
        root = await getTemporaryDirectory();
      } on Object {
        root = Directory.systemTemp;
      }
      temp = await root.createTemp('knowit_apkg_export_');
      dbFile = File('${temp.path}/collection.anki2');
      db = sqlite3.open(dbFile.path);
      _createSchema(db, nowSeconds, nowMs, models, deckRows);

      var noteIndex = 0;
      var cardIndex = 0;
      for (final group in notes.values) {
        // Deterministic ordering makes exported files reproducible.
        group.sort((a, b) => a.id.compareTo(b.id));
        final primary = group.first;
        final deck = HiveService.getCollection(primary.collectionId);
        final resolvedPath = deck == null
            ? 'Default'
            : _deckPath(collections, deck);
        final did = deckIds[resolvedPath] ?? 1;
        final noteId = 1700000000000 + noteIndex;
        final specs = const NoteService().specsFor(
          primary.type,
          primary.frontText,
        );
        final modelId = switch (primary.type) {
          CardType.basic => _basicModelId,
          CardType.reversed => _reversedModelId,
          CardType.cloze => _clozeModelId,
        };

        var front = markupToAnkiHtml(primary.frontText);
        var back = markupToAnkiHtml(primary.backText);
        final mediaRefs = <String>[];
        final imageName = _addMedia(
          media,
          primary.imagePath,
          noteIndex,
          warnings,
        );
        final audioName = _addMedia(
          media,
          primary.audioPath,
          noteIndex,
          warnings,
        );
        if (imageName != null) {
          front = '$front<br><img src="$imageName">';
          back = '$back<br><img src="$imageName">';
          mediaRefs.add(imageName);
        }
        if (audioName != null) {
          front = '$front<br>[sound:$audioName]';
          back = '$back<br>[sound:$audioName]';
          mediaRefs.add(audioName);
        }
        final fields = '$front\x1f$back';
        final tags = primary.tags.isEmpty ? '' : ' ${primary.tags.join(' ')} ';
        db.execute(
          'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, '
          'csum, flags, data) VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, \'\')',
          [
            noteId,
            _guid(noteIndex),
            modelId,
            nowSeconds,
            tags,
            fields,
            front,
            _checksum(primary.frontText),
          ],
        );

        for (var specIndex = 0; specIndex < specs.length; specIndex++) {
          final spec = specs[specIndex];
          final cardId = 1710000000000 + cardIndex;
          cardIndex++;
          final due = cardIndex;
          final ord = primary.type == CardType.cloze
              ? (spec.clozeIndex - 1).clamp(0, 999)
              : specIndex;
          db.execute(
            'INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, '
            'ivl, factor, reps, lapses, left, odue, odid, flags, data) '
            'VALUES (?, ?, ?, ?, ?, -1, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, \'\')',
            [cardId, noteId, did, ord, nowSeconds, due],
          );
        }
        noteIndex++;
      }

      // Verify the generated SQLite database before packaging it.
      final integrity = db.select('PRAGMA integrity_check');
      db.close();
      db = null;
      final integrityValue = integrity.isEmpty
          ? 'not ok'
          : integrity.first.values.first.toString();
      if (integrityValue.toLowerCase() != 'ok') {
        throw const AnkiExportException(
          'The generated Anki database failed its integrity check.',
        );
      }

      final dbBytes = await dbFile.readAsBytes();
      final archive = Archive();
      archive.addFile(ArchiveFile('collection.anki2', dbBytes.length, dbBytes));
      final mediaManifest = <String, String>{};
      var mediaIndex = 0;
      for (final entry in media.entries) {
        final name = '$mediaIndex';
        mediaManifest[name] = entry.key;
        archive.addFile(ArchiveFile(name, entry.value.length, entry.value));
        mediaIndex++;
      }
      final mediaJson = utf8.encode(jsonEncode(mediaManifest));
      archive.addFile(ArchiveFile('media', mediaJson.length, mediaJson));
      final encoded = ZipEncoder().encode(archive);

      return AnkiExportResult(
        bytes: Uint8List.fromList(encoded),
        fileName: 'knowit-export-${dayKey(DateTime.now())}.apkg',
        notes: noteIndex,
        cards: cardIndex,
        media: media.length,
        warnings: warnings,
      );
    } on AnkiExportException {
      rethrow;
    } on Object catch (error) {
      throw AnkiExportException('Could not create the Anki package. $error');
    } finally {
      try {
        db?.close();
        if (dbFile != null && dbFile.existsSync()) dbFile.deleteSync();
        if (temp != null && temp.existsSync()) temp.deleteSync(recursive: true);
      } on Object {
        // Cleanup must not mask the result.
      }
    }
  }

  Future<bool> saveAs(AnkiExportResult result) async {
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: AppLocalizations.current.bi(
          'Save Anki package',
          'Сохранить пакет Anki',
        ),
        fileName: result.fileName,
        bytes: result.bytes,
        mimeType: 'application/octet-stream',
      );
      return uri != null;
    } on Object {
      return false;
    }
  }

  void _createSchema(
    Database db,
    int nowSeconds,
    int nowMs,
    Map<int, Map<String, dynamic>> models,
    List<Map<String, dynamic>> decks,
  ) {
    db.execute('''
      CREATE TABLE col (
        id integer primary key, crt integer not null, mod integer not null,
        scm integer not null, ver integer not null, dty integer not null,
        usn integer not null, ls integer not null, conf text not null,
        models text not null, decks text not null, dconf text not null,
        tags text not null
      )
    ''');
    db.execute('''
      CREATE TABLE notes (
        id integer primary key, guid text not null, mid integer not null,
        mod integer not null, usn integer not null, tags text not null,
        flds text not null, sfld integer not null, csum integer not null,
        flags integer not null, data text not null
      )
    ''');
    db.execute('''
      CREATE TABLE cards (
        id integer primary key, nid integer not null, did integer not null,
        ord integer not null, mod integer not null, usn integer not null,
        type integer not null, queue integer not null, due integer not null,
        ivl integer not null, factor integer not null, reps integer not null,
        lapses integer not null, left integer not null, odue integer not null,
        odid integer not null, flags integer not null, data text not null
      )
    ''');
    db.execute('''
      CREATE TABLE revlog (
        id integer primary key, cid integer not null, usn integer not null,
        ease integer not null, ivl integer not null, lastIvl integer not null,
        factor integer not null, time integer not null, type integer not null
      )
    ''');
    db.execute(
      'CREATE TABLE graves (usn integer not null, oid integer not null, '
      'type integer not null)',
    );
    db.execute('CREATE INDEX ix_notes_usn ON notes (usn)');
    db.execute('CREATE INDEX ix_cards_usn ON cards (usn)');
    db.execute('CREATE INDEX ix_cards_nid ON cards (nid)');
    db.execute('CREATE INDEX ix_cards_sched ON cards (did, queue, due)');

    final deckJson = <String, dynamic>{
      for (final deck in decks) '${deck['id']}': deck,
    };
    final confJson = {
      'activeDecks': [1],
      'curDeck': 1,
      'newSpread': 0,
      'collapseTime': 1200,
      'timeLim': 0,
      'estTimes': true,
      'dueCounts': true,
      'curModel': 1600000000001,
      'nextPos': 1,
      'sortType': 'noteFld',
      'sortBackwards': false,
      'addToCur': true,
    };
    final dconfJson = {
      '1': {
        'id': 1,
        'name': 'Default',
        'new': {
          'delays': [1, 10],
          'ints': [1, 4, 0],
          'initialFactor': 2500,
          'order': 1,
          'perDay': 20,
        },
        'lapse': {
          'delays': [10],
          'mult': 0,
          'minInt': 1,
          'leechFails': 8,
          'leechAction': 0,
        },
        'rev': {
          'perDay': 200,
          'ease4': 1.3,
          'fuzz': 0.05,
          'minSpace': 1,
          'ivlFct': 1,
          'maxIvl': 36500,
          'bury': false,
        },
        'maxTaken': 60,
        'timer': 0,
        'autoplay': true,
        'replayq': true,
        'mod': 0,
        'usn': 0,
        'dyn': false,
      },
    };
    db.execute(
      'INSERT INTO col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, '
      'decks, dconf, tags) VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, ?)',
      [
        nowSeconds,
        nowMs,
        nowMs,
        jsonEncode(confJson),
        jsonEncode({
          for (final entry in models.entries) '${entry.key}': entry.value,
        }),
        jsonEncode(deckJson),
        jsonEncode(dconfJson),
        '{}',
      ],
    );
  }

  Map<String, dynamic> _deckJson(int id, String path) => {
    'id': id,
    'name': path,
    'conf': 1,
    'desc': '',
    'dyn': 0,
    'collapsed': false,
    'browserCollapsed': false,
    'newToday': [0, 0],
    'revToday': [0, 0],
    'lrnToday': [0, 0],
    'timeToday': [0, 0],
    'mod': 0,
    'usn': -1,
  };

  Map<String, dynamic> _modelJson({
    required int id,
    required String name,
    required int type,
    required List<Map<String, String>> templates,
    required List<List<dynamic>> req,
  }) {
    final labels = type == 1 ? ['Text', 'Back Extra'] : ['Front', 'Back'];
    return {
      'id': id,
      'name': name,
      'type': type,
      'mod': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'usn': 0,
      'sortf': 0,
      'did': 1,
      'tags': <String>[],
      'vers': <String>[],
      'css': _css,
      'latexPre':
          '\\documentclass[12pt]{article}\\special{papersize=3in,5in}'
          '\\usepackage[utf8]{inputenc}\\usepackage{amssymb,amsmath}'
          '\\pagestyle{empty}\\setlength{\\parindent}{0in}\\begin{document}',
      'latexPost': '\\end{document}',
      'latexsvg': false,
      'req': req,
      'flds': [
        for (var index = 0; index < labels.length; index++)
          {
            'name': labels[index],
            'ord': index,
            'font': 'Arial',
            'size': 20,
            'media': <String>[],
            'sticky': false,
            'rtl': false,
            'plainText': false,
          },
      ],
      'tmpls': [
        for (var index = 0; index < templates.length; index++)
          {
            'name': templates[index]['name'],
            'ord': index,
            'qfmt': templates[index]['qfmt'],
            'afmt': templates[index]['afmt'],
            'bqfmt': '',
            'bafmt': '',
            'did': null,
            'bfont': 'Arial',
            'bsize': 20,
            'id': id + 100 + index,
          },
      ],
    };
  }

  String _deckPath(List<Collection> collections, Collection deck) {
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

  String? _addMedia(
    Map<String, Uint8List> media,
    String? path,
    int noteIndex,
    List<String> warnings,
  ) {
    if (path == null || path.trim().isEmpty) return null;
    try {
      final file = File(path);
      if (!file.existsSync()) {
        warnings.add(
          AppLocalizations.current.bi(
            'A media file was missing and was skipped in export.',
            'Медиафайл отсутствовал и был пропущен при экспорте.',
          ),
        );
        return null;
      }
      final original = file.uri.pathSegments.last;
      final safe = original.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      var name = '${noteIndex}_$safe';
      var suffix = 1;
      while (media.containsKey(name)) {
        name = '${noteIndex}_${suffix}_$safe';
        suffix++;
      }
      media[name] = file.readAsBytesSync();
      return name;
    } on Object {
      warnings.add(
        AppLocalizations.current.bi(
          'A media file could not be read and was skipped in export.',
          'Медиафайл не удалось прочитать, он пропущен при экспорте.',
        ),
      );
      return null;
    }
  }

  String _guid(int index) {
    final basis = 'knowit-${DateTime.now().microsecondsSinceEpoch}-$index';
    return base64Url.encode(utf8.encode(basis)).replaceAll('=', '');
  }

  int _checksum(String text) {
    var hash = 0;
    for (final code in text.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash;
  }
}
