import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/note_service.dart';
import 'package:knowit/services/settings_service.dart';
import 'package:knowit/utils/formatters.dart';
import 'package:knowit/utils/id_generator.dart';
import 'package:knowit/utils/import_progress.dart';
import 'package:path_provider/path_provider.dart';

class BackupFileInfo {
  final String path;
  final String name;
  final DateTime modified;
  final int sizeBytes;

  const BackupFileInfo({
    required this.path,
    required this.name,
    required this.modified,
    required this.sizeBytes,
  });

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class BackupImportResult {
  final int collections;
  final int cards;
  final int logs;
  final bool replaced;

  const BackupImportResult({
    required this.collections,
    required this.cards,
    required this.logs,
    required this.replaced,
  });

  String get summary => AppLocalizations.current.backupSummary(
    collections,
    cards,
    logs,
    replaced,
  );
}

class BackupData {
  final List<Collection> collections;
  final List<CardItem> cards;
  final List<ReviewLog> logs;
  final Map<String, dynamic>? settings;
  final DateTime exportedAt;

  const BackupData({
    required this.collections,
    required this.cards,
    required this.logs,
    this.settings,
    required this.exportedAt,
  });
}

/// JSON backup, restore and merge. Deliberately avoids proprietary formats so
/// users always own their data. APKG import/export is not implemented.
class BackupService {
  static const String formatName = 'knowit-backup';
  static const int formatVersion = 1;
  static const int maxImportCharacters = 50 * 1024 * 1024;

  static String exportToJson() {
    final data = {
      'format': formatName,
      'version': formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'collections': HiveService.getAllCollections()
          .map((deck) => deck.toJson())
          .toList(),
      'cards': HiveService.getAllCards().map((card) => card.toJson()).toList(),
      'logs': HiveService.getAllLogs().map((log) => log.toJson()).toList(),
      'settings': SettingsService.value.toMap(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  static BackupData parse(String raw) {
    if (raw.trim().isEmpty) {
      throw FormatException(
        AppLocalizations.current.bi(
          'The backup is empty.',
          'Резервная копия пуста.',
        ),
      );
    }
    if (raw.length > maxImportCharacters) {
      throw FormatException(
        AppLocalizations.current.bi(
          'The backup is too large to import.',
          'Резервная копия слишком большая для импорта.',
        ),
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw FormatException(
        AppLocalizations.current.bi(
          'This is not valid JSON. Check that you pasted the complete backup.',
          'Это не корректный JSON. Убедитесь, что вставлена полная резервная '
              'копия.',
        ),
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        AppLocalizations.current.bi(
          'The backup must be a JSON object.',
          'Резервная копия должна быть объектом JSON.',
        ),
      );
    }
    if (decoded['format'] != null && decoded['format'] != formatName) {
      throw FormatException(
        AppLocalizations.current.bi(
          'This file is not a KnowIt backup.',
          'Этот файл не является резервной копией KnowIt.',
        ),
      );
    }

    final rawCollections = decoded['collections'];
    final rawCards = decoded['cards'];
    if (rawCollections is! List || rawCards is! List) {
      throw FormatException(
        AppLocalizations.current.bi(
          'The backup is missing its deck or card list.',
          'В резервной копии отсутствует список колод или карточек.',
        ),
      );
    }

    final collections = <Collection>[];
    for (final item in rawCollections) {
      if (item is Map<String, dynamic>) {
        final deck = Collection.fromJson(item);
        if (deck.name.trim().isNotEmpty) collections.add(deck);
      }
    }

    final cards = <CardItem>[];
    for (final item in rawCards) {
      if (item is Map<String, dynamic>) {
        final card = CardItem.fromJson(item);
        if (card.frontText.trim().isNotEmpty) cards.add(card);
      }
    }
    if (collections.isEmpty && cards.isEmpty) {
      throw FormatException(
        AppLocalizations.current.bi(
          'The backup does not contain any data.',
          'Резервная копия не содержит данных.',
        ),
      );
    }

    final logs = <ReviewLog>[];
    final rawLogs = decoded['logs'];
    if (rawLogs is List) {
      for (final item in rawLogs) {
        if (item is Map<String, dynamic>) {
          try {
            logs.add(ReviewLog.fromJson(item));
          } on Object {
            // Skip a single malformed review instead of rejecting the backup.
          }
        }
      }
    }

    final rawSettings = decoded['settings'];
    return BackupData(
      collections: collections,
      cards: cards,
      logs: logs,
      settings: rawSettings is Map<String, dynamic> ? rawSettings : null,
      exportedAt:
          DateTime.tryParse(decoded['exportedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Imports [raw]. In merge mode all imported content receives fresh ids when
  /// it would collide with existing records; nothing is overwritten. In replace
  /// mode the database is replaced after validation (the UI asks for explicit
  /// confirmation first).
  static Future<BackupImportResult> importJson(
    String raw, {
    bool replace = false,
    void Function(ImportProgress progress)? onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    final eta = EtaEstimator();
    void report(double? fraction, String stage, [String? detail]) {
      if (onProgress != null) {
        onProgress(
          ImportProgress(
            fraction: fraction,
            stage: stage,
            detail: detail,
            eta: eta.update(fraction),
          ),
        );
      }
    }

    cancellationToken?.throwIfCancelled();
    report(0.10, 'Parsing backup data…');
    await HiveService.ensureReady();
    final data = parse(raw);

    cancellationToken?.throwIfCancelled();
    report(0.25, 'Validating collection structure…');

    final existingCollections = replace
        ? <Collection>[]
        : HiveService.getAllCollections();
    final existingCards = replace ? <CardItem>[] : HiveService.getAllCards();
    final existingLogs = replace ? <ReviewLog>[] : HiveService.getAllLogs();

    final usedCollectionIds = existingCollections
        .map((deck) => deck.id)
        .toSet();
    final usedCardIds = existingCards.map((card) => card.id).toSet();
    final usedLogIds = existingLogs.map((log) => log.id).toSet();

    final collectionIdMap = <String, String>{};
    for (final deck in data.collections) {
      var id = deck.id;
      if (id.isEmpty || usedCollectionIds.contains(id)) id = newId();
      collectionIdMap[deck.id] = id;
      usedCollectionIds.add(id);
    }

    final importedCollections = <Collection>[];
    for (var index = 0; index < data.collections.length; index++) {
      final deck = data.collections[index];
      final parentOriginal = deck.parentId;
      var parentId = parentOriginal == null
          ? null
          : collectionIdMap[parentOriginal];
      if (parentId == null &&
          parentOriginal != null &&
          existingCollections.any((item) => item.id == parentOriginal)) {
        parentId = parentOriginal;
      }
      importedCollections.add(
        deck.copyWith(
          id: collectionIdMap[deck.id]!,
          parentId: parentId,
          name: deck.name.trim().isEmpty ? 'Imported deck' : deck.name.trim(),
          updatedAt: DateTime.now(),
          sortOrder: deck.sortOrder == 0
              ? existingCollections.length + index
              : deck.sortOrder,
        ),
      );
    }

    // Reject cyclic parent chains so imported decks can never become invisible.
    final byId = {for (final deck in importedCollections) deck.id: deck};
    for (var index = 0; index < importedCollections.length; index++) {
      final deck = importedCollections[index];
      var parentId = deck.parentId;
      if (parentId == null) continue;
      final visited = <String>{deck.id};
      var cycle = false;
      while (parentId != null) {
        if (!visited.add(parentId)) {
          cycle = true;
          break;
        }
        parentId = byId[parentId]?.parentId;
      }
      if (cycle) {
        importedCollections[index] = deck.copyWith(parentId: null);
      }
    }

    // Cards referencing a deck that is not part of the backup and not present
    // locally are placed in a recovery deck instead of being dropped.
    String? recoveryDeckId;
    bool needsRecoveryDeck(List<CardItem> source) => source.any((card) {
      final imported = collectionIdMap.containsKey(card.collectionId);
      final existing = existingCollections.any(
        (deck) => deck.id == card.collectionId,
      );
      return !imported && !existing;
    });

    if (needsRecoveryDeck(data.cards)) {
      final recovered = Collection(
        id: newId(),
        name: 'Imported cards',
        emoji: '📥',
        colorValue: 0xFFFFC107,
        description:
            'Cards restored from a backup without their original deck.',
      );
      recoveryDeckId = recovered.id;
      importedCollections.add(recovered);
    }

    // Older KnowIt backups stored reversed/cloze notes as a single card. Expand
    // them into independently scheduled siblings while preserving the original
    // card id and its review-log mapping.
    final sourceCards = <CardItem>[];
    for (final card in data.cards) {
      if (card.noteId == null &&
          (card.type == CardType.reversed || card.type == CardType.cloze)) {
        sourceCards.addAll(const NoteService().migrateLegacyCard(card));
      } else {
        sourceCards.add(card);
      }
    }

    final importedCards = <CardItem>[];
    final cardIdMap = <String, String>{};
    final noteIdMap = <String, String>{};
    for (final card in sourceCards) {
      var id = card.id;
      if (id.isEmpty || usedCardIds.contains(id)) id = newId();
      usedCardIds.add(id);
      cardIdMap[card.id] = id;

      final targetDeck =
          collectionIdMap[card.collectionId] ??
          (existingCollections.any((deck) => deck.id == card.collectionId)
              ? card.collectionId
              : recoveryDeckId);
      if (targetDeck == null) continue;

      final mappedNoteId = noteIdMap.putIfAbsent(card.noteKey, () => newId());

      importedCards.add(
        card.copyWith(
          id: id,
          noteId: mappedNoteId,
          collectionId: targetDeck,
          updatedAt: DateTime.now(),
        ),
      );
    }

    final importedLogs = <ReviewLog>[];
    for (final log in data.logs) {
      final mappedCardId = cardIdMap[log.cardId];
      if (mappedCardId == null) continue;
      var id = log.id;
      if (id.isEmpty || usedLogIds.contains(id)) id = newId();
      usedLogIds.add(id);
      importedLogs.add(
        ReviewLog.fromJson({...log.toJson(), 'id': id, 'cardId': mappedCardId}),
      );
    }

    cancellationToken?.throwIfCancelled();
    report(0.60, 'Saving backup data…', '(${importedCards.length} cards)');

    if (replace) {
      await HiveService.replaceAll(
        collections: importedCollections,
        cards: importedCards,
        logs: importedLogs,
      );
      final settingsMap = data.settings;
      if (settingsMap != null) {
        await SettingsService.save(AppSettings.fromMap(settingsMap));
      }
    } else {
      for (final deck in importedCollections) {
        await HiveService.createCollection(deck);
      }
      await HiveService.saveCards(importedCards);
      await HiveService.addLogs(importedLogs);
      await HiveService.refreshCardCounts();
    }

    report(1.0, 'Backup restoration complete.');

    return BackupImportResult(
      collections: importedCollections.length,
      cards: importedCards.length,
      logs: importedLogs.length,
      replaced: replace,
    );
  }

  static Future<Directory?> _backupDirectory({bool create = false}) async {
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/knowit_backups');
      if (create && !directory.existsSync()) {
        await directory.create(recursive: true);
      }
      return directory;
    } on Object {
      return null;
    }
  }

  /// Writes a timestamped backup file. Returns null on platforms without a
  /// writable documents directory (for example web); callers can then fall back
  /// to sharing the JSON text.
  static Future<BackupFileInfo?> writeBackupFile([String? json]) async {
    final directory = await _backupDirectory(create: true);
    if (directory == null) return null;
    final now = DateTime.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final file = File('${directory.path}/knowit-$stamp.json');
    final content = json ?? exportToJson();
    await file.writeAsString(content, flush: true);
    final stat = await file.stat();
    return BackupFileInfo(
      path: file.path,
      name: file.uri.pathSegments.last,
      modified: stat.modified,
      sizeBytes: stat.size,
    );
  }

  /// Opens the platform save dialog and writes the backup where the user
  /// chooses. Returns false when cancelled or unsupported.
  static Future<bool> saveBackupAs(String json, {String? fileName}) async {
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Save KnowIt backup',
        fileName: fileName ?? suggestedFileName(),
        bytes: Uint8List.fromList(utf8.encode(json)),
        mimeType: 'application/json',
      );
      return uri != null;
    } on Object {
      return false;
    }
  }

  /// Opens the platform file picker and returns the selected backup text.
  /// Returns null when cancelled or unreadable.
  static Future<String?> pickBackupJson() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: 'Choose a KnowIt backup',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (files.isEmpty) return null;
      final bytes = await files.first.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } on Object {
      return null;
    }
  }

  static Future<List<BackupFileInfo>> listBackups() async {
    final directory = await _backupDirectory();
    if (directory == null || !directory.existsSync()) return const [];
    final files = await directory.list().where((item) => item is File).toList();
    final result = <BackupFileInfo>[];
    for (final item in files) {
      if (!item.path.endsWith('.json')) continue;
      final stat = await item.stat();
      result.add(
        BackupFileInfo(
          path: item.path,
          name: item.uri.pathSegments.last,
          modified: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }
    result.sort((a, b) => b.modified.compareTo(a.modified));
    return result;
  }

  static Future<String?> readBackupFile(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return await file.readAsString();
    } on Object {
      return null;
    }
  }

  static Future<bool> deleteBackupFile(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      await file.delete();
      return true;
    } on Object {
      return false;
    }
  }

  /// Backups older than 30 days are pruned automatically when a new manual
  /// backup is created.
  static Future<void> pruneOldBackups({int keep = 10}) async {
    final backups = await listBackups();
    if (backups.length <= keep) return;
    for (final backup in backups.skip(keep)) {
      await deleteBackupFile(backup.path);
    }
  }

  static String suggestedFileName() => 'knowit-${dayKey(DateTime.now())}.json';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
