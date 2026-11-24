import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/services/media_service.dart';
import 'package:knowit/services/note_service.dart';
import 'package:knowit/services/sync/tombstone_store.dart';
import 'package:knowit/utils/id_generator.dart';
import 'package:path_provider/path_provider.dart';

/// Snapshot of everything removed together with a deck, used for undo.
class DeckDeletionSnapshot {
  final Collection collection;
  final List<Collection> subdecks;
  final List<CardItem> cards;
  final List<ReviewLog> logs;

  const DeckDeletionSnapshot({
    required this.collection,
    required this.subdecks,
    required this.cards,
    required this.logs,
  });

  int get cardCount => cards.length;
}

/// Single source of truth for local persistence.
///
/// Boxes are keyed by stable record ids (not indexes) so edits, moves and undo
/// can never touch the wrong record. Existing installations that used
/// auto-increment keys are migrated on startup without deleting any content.
class HiveService {
  static const String cardsBoxName = 'cards';
  static const String collectionsBoxName = 'collections';
  static const String logsBoxName = 'review_logs';
  static const String metaBoxName = 'meta';
  static const String syncBoxName = 'sync_meta';
  static const int schemaVersion = 3;

  static late Box<CardItem> _cardsBox;
  static late Box<Collection> _collectionsBox;
  static late Box<ReviewLog> _logsBox;
  static late Box _metaBox;
  static late Box _syncBox;
  static bool _initialized = false;

  static Future<void> init({String? directory}) async {
    if (_initialized) return;
    if (directory == null) {
      final support = await getApplicationSupportDirectory();
      final storage = Directory(support.path);
      if (!storage.existsSync()) {
        await storage.create(recursive: true);
      }
      await _migrateLegacyStorage(storage);
      Hive.init(storage.path);
    } else {
      Hive.init(directory);
    }

    _registerAdapters();

    _cardsBox = await Hive.openBox<CardItem>(cardsBoxName);
    _collectionsBox = await Hive.openBox<Collection>(collectionsBoxName);
    _logsBox = await Hive.openBox<ReviewLog>(logsBoxName);
    _metaBox = await Hive.openBox(metaBoxName);
    _syncBox = await Hive.openBox(syncBoxName);
    await TombstoneStore.attach(_syncBox);

    await _migrate();
    _initialized = true;
  }

  /// Reopens boxes if the platform or another isolate closed them. Import
  /// operations call this before writing so a transient file close can never
  /// surface as "File closed" in the middle of a restore.
  static Future<void> ensureReady() async {
    if (!_initialized) {
      await init();
      return;
    }
    try {
      if (!_cardsBox.isOpen) {
        _cardsBox = await Hive.openBox<CardItem>(cardsBoxName);
      }
      if (!_collectionsBox.isOpen) {
        _collectionsBox = await Hive.openBox<Collection>(collectionsBoxName);
      }
      if (!_logsBox.isOpen) {
        _logsBox = await Hive.openBox<ReviewLog>(logsBoxName);
      }
      if (!_metaBox.isOpen) {
        _metaBox = await Hive.openBox(metaBoxName);
      }
      if (!_syncBox.isOpen) {
        _syncBox = await Hive.openBox(syncBoxName);
        await TombstoneStore.attach(_syncBox);
      }
    } on Object {
      _initialized = false;
      await init();
    }
  }

  /// Older KnowIt builds stored Hive boxes in the user's Documents folder.
  /// Move them once into the per-user app support directory and remove the
  /// legacy copies after a successful move.
  static Future<void> _migrateLegacyStorage(Directory destination) async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      if (documents.path == destination.path) return;
      const names = [
        cardsBoxName,
        collectionsBoxName,
        logsBoxName,
        metaBoxName,
        syncBoxName,
        'settings',
      ];
      for (final name in names) {
        for (final extension in ['.hive', '.hivec']) {
          final source = File(
            '${documents.path}${Platform.pathSeparator}$name$extension',
          );
          if (!source.existsSync()) continue;
          final target = File(
            '${destination.path}${Platform.pathSeparator}$name$extension',
          );
          if (!target.existsSync() || target.lengthSync() == 0) {
            await source.copy(target.path);
            await source.delete();
          } else if (source.lengthSync() == 0 ||
              !source.lastModifiedSync().isAfter(target.lastModifiedSync())) {
            await source.delete();
          }
        }
        final lock = File(
          '${documents.path}${Platform.pathSeparator}$name.lock',
        );
        if (lock.existsSync()) {
          await lock.delete();
        }
      }
      await _moveLegacyDirectory(
        Directory('${documents.path}${Platform.pathSeparator}knowit_media'),
        Directory('${destination.path}${Platform.pathSeparator}knowit_media'),
      );
      await _moveLegacyDirectory(
        Directory(
          '${documents.path}${Platform.pathSeparator}knowit_backups',
        ),
        Directory(
          '${destination.path}${Platform.pathSeparator}knowit_backups',
        ),
      );
    } on Object catch (error) {
      debugPrint('KnowIt storage migration skipped: $error');
    }
  }

  static Future<void> _moveLegacyDirectory(
    Directory source,
    Directory destination,
  ) async {
    if (!source.existsSync()) return;
    if (!destination.existsSync()) {
      await destination.create(recursive: true);
    }
    await for (final entity in source.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(source.path.length + 1);
      final target = File(
        '${destination.path}${Platform.pathSeparator}$relative',
      );
      if (!target.existsSync()) {
        await target.parent.create(recursive: true);
        await entity.copy(target.path);
      }
      await entity.delete();
    }
    try {
      await source.delete(recursive: true);
    } on Object {
      // Best effort only; the files have already been copied.
    }
  }

  static void _registerAdapters() {
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(CardItemAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(CollectionAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ReviewLogAdapter());
  }

  /// Normalizes legacy indexes into ids, removes duplicate ids and repairs
  /// references. Safe to run on every startup; the fast path skips rewriting
  /// once the schema is current.
  static Future<void> _migrate() async {
    final version = _metaBox.get('schema_version', defaultValue: 0) as int;
    final keysAreIds =
        _collectionsBox.keys.every(
          (key) => key is String && _collectionsBox.get(key)?.id == key,
        ) &&
        _cardsBox.keys.every(
          (key) => key is String && _cardsBox.get(key)?.id == key,
        ) &&
        _logsBox.keys.every(
          (key) => key is String && _logsBox.get(key)?.id == key,
        );
    if (version >= schemaVersion && keysAreIds) return;

    final collections = _collectionsBox.values.toList();
    final cards = _cardsBox.values.toList();

    final usedCollectionIds = <String>{};
    final collectionIdRemap = <String, String>{};
    final normalizedCollections = <Collection>[];

    for (var index = 0; index < collections.length; index++) {
      final collection = collections[index];
      var id = collection.id;
      if (id.trim().isEmpty || usedCollectionIds.contains(id)) {
        final replacement = newId();
        if (collection.id.isNotEmpty) {
          collectionIdRemap[collection.id] = replacement;
        }
        id = replacement;
      }
      usedCollectionIds.add(id);
      normalizedCollections.add(
        collection.copyWith(
          id: id,
          name: collection.name.trim().isEmpty
              ? 'Untitled deck'
              : collection.name,
          sortOrder: collection.sortOrder == 0 ? index : collection.sortOrder,
          updatedAt: collection.updatedAt,
        ),
      );
    }

    String resolveCollectionId(String original) {
      if (usedCollectionIds.contains(original)) return original;
      final remapped = collectionIdRemap[original];
      if (remapped != null) return remapped;
      return original;
    }

    var orphanDeckId = '';
    final hasOrphans = cards.any(
      (card) =>
          !usedCollectionIds.contains(resolveCollectionId(card.collectionId)),
    );
    if (hasOrphans) {
      final recovered = Collection(
        id: newId(),
        name: 'Recovered cards',
        emoji: '🧩',
        colorValue: 0xFFFFC107,
        description:
            'Cards whose original deck could not be found. Nothing was lost.',
      );
      orphanDeckId = recovered.id;
      normalizedCollections.add(recovered);
      usedCollectionIds.add(recovered.id);
    }

    final usedCardIds = <String>{};
    final normalizedCards = <CardItem>[];
    final generatedSiblings = <CardItem>[];
    for (final card in cards) {
      var id = card.id;
      if (id.trim().isEmpty || usedCardIds.contains(id)) id = newId();
      usedCardIds.add(id);
      var collectionId = resolveCollectionId(card.collectionId);
      if (!usedCollectionIds.contains(collectionId)) {
        collectionId = orphanDeckId;
      }
      var normalized = card.copyWith(
        id: id,
        collectionId: collectionId,
        tags: card.tags
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList(),
      );

      final neededSiblingMigration = version < 3 && card.noteId == null;
      if (neededSiblingMigration) {
        final migrated = const NoteService().migrateLegacyCard(normalized);
        normalized = migrated.first;
        generatedSiblings.addAll(migrated.skip(1));
      } else if (normalized.noteId == null) {
        normalized = normalized.copyWith(noteId: id);
      }

      normalizedCards.add(normalized);
    }
    for (final sibling in generatedSiblings) {
      var id = sibling.id;
      while (usedCardIds.contains(id)) {
        id = newId();
      }
      usedCardIds.add(id);
      normalizedCards.add(sibling.copyWith(id: id));
    }

    await _rewriteCollections(normalizedCollections);
    await _rewriteCards(normalizedCards);
    await _rewriteLogs();
    await refreshCardCounts();
    await _metaBox.put('schema_version', schemaVersion);
  }

  static Future<void> _rewriteCollections(List<Collection> collections) async {
    for (final collection in collections) {
      await _collectionsBox.put(collection.id, collection);
    }
    for (final key in _collectionsBox.keys.toList()) {
      final value = _collectionsBox.get(key);
      if (key is int || value == null || value.id != key) {
        await _collectionsBox.delete(key);
      }
    }
  }

  static Future<void> _rewriteCards(List<CardItem> cards) async {
    for (final card in cards) {
      await _cardsBox.put(card.id, card);
    }
    for (final key in _cardsBox.keys.toList()) {
      final value = _cardsBox.get(key);
      if (key is int || value == null || value.id != key) {
        await _cardsBox.delete(key);
      }
    }
  }

  static Future<void> _rewriteLogs() async {
    for (final log in _logsBox.values.toList()) {
      await _logsBox.put(log.id, log);
    }
    for (final key in _logsBox.keys.toList()) {
      final value = _logsBox.get(key);
      if (key is int || value == null || value.id != key) {
        await _logsBox.delete(key);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Decks
  // ---------------------------------------------------------------------------

  static ValueListenable<Box<Collection>> get collectionsListenable =>
      _collectionsBox.listenable();

  static ValueListenable<Box<CardItem>> get cardsListenable =>
      _cardsBox.listenable();

  static ValueListenable<Box<ReviewLog>> get logsListenable =>
      _logsBox.listenable();

  static List<Collection> getAllCollections() {
    final result = _collectionsBox.values.toList();
    result.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) return order;
      return a.createdAt.compareTo(b.createdAt);
    });
    return result;
  }

  static Collection? getCollection(String id) => _collectionsBox.get(id);

  static Collection? getCollectionByName(String name) {
    final needle = name.trim().toLowerCase();
    for (final collection in _collectionsBox.values) {
      if (collection.name.trim().toLowerCase() == needle) return collection;
    }
    return null;
  }

  static Future<void> saveCollection(Collection collection) async {
    await _collectionsBox.put(collection.id, collection);
  }

  static Future<Collection> createCollection(Collection collection) async {
    await _collectionsBox.put(collection.id, collection);
    return collection;
  }

  static Future<void> updateCollection(Collection collection) async {
    await _collectionsBox.put(
      collection.id,
      collection.copyWith(updatedAt: DateTime.now()),
    );
  }

  static Future<DeckDeletionSnapshot?> deleteCollectionCascade(
    String collectionId,
  ) async {
    final collection = _collectionsBox.get(collectionId);
    if (collection == null) return null;

    final allCollections = getAllCollections();
    final removedDeckIds = _descendantIds(allCollections, collectionId);
    removedDeckIds.add(collectionId);

    final removedDecks = allCollections
        .where((deck) => removedDeckIds.contains(deck.id))
        .toList();
    final removedCards = _cardsBox.values
        .where((card) => removedDeckIds.contains(card.collectionId))
        .toList();
    final removedCardIds = removedCards.map((card) => card.id).toSet();
    final removedLogs = _logsBox.values
        .where((log) => removedCardIds.contains(log.cardId))
        .toList();

    // Perform batched deletions across boxes for instantaneous durability
    final removedLogIds = removedLogs.map((log) => log.id).toList();
    if (removedLogIds.isNotEmpty) {
      await _logsBox.deleteAll(removedLogIds);
    }
    if (removedCardIds.isNotEmpty) {
      await _cardsBox.deleteAll(removedCardIds);
      await TombstoneStore.addAll(SyncEntityType.card, removedCardIds);
    }
    await _collectionsBox.deleteAll(removedDeckIds);
    await TombstoneStore.addAll(SyncEntityType.collection, removedDeckIds);

    await refreshCardCounts();

    return DeckDeletionSnapshot(
      collection: collection,
      subdecks: removedDecks.where((deck) => deck.id != collectionId).toList(),
      cards: removedCards,
      logs: removedLogs,
    );
  }

  static Future<void> restoreDeckSnapshot(DeckDeletionSnapshot snapshot) async {
    final deckMap = <String, Collection>{
      for (final deck in snapshot.subdecks) deck.id: deck,
      snapshot.collection.id: snapshot.collection,
    };
    await _collectionsBox.putAll(deckMap);
    await TombstoneStore.removeAll(SyncEntityType.collection, deckMap.keys);

    if (snapshot.cards.isNotEmpty) {
      final cardMap = {for (final card in snapshot.cards) card.id: card};
      await _cardsBox.putAll(cardMap);
      await TombstoneStore.removeAll(SyncEntityType.card, cardMap.keys);
    }

    if (snapshot.logs.isNotEmpty) {
      final logMap = {for (final log in snapshot.logs) log.id: log};
      await _logsBox.putAll(logMap);
    }

    await refreshCardCounts();
  }

  /// Asynchronously scans managed media directory and removes orphaned files
  /// no longer referenced by any card in the database.
  /// Preserves shared media and runs safely in the background.
  static Future<int> cleanupOrphanedMedia() async {
    try {
      final activeMedia = <String>{};
      for (final card in _cardsBox.values) {
        if (card.imagePath != null && card.imagePath!.isNotEmpty) {
          activeMedia.add(MediaService.sanitizeFileName(card.imagePath!));
        }
        if (card.audioPath != null && card.audioPath!.isNotEmpty) {
          activeMedia.add(MediaService.sanitizeFileName(card.audioPath!));
        }
      }

      final mediaDir = await MediaService.getMediaDirectory();
      if (!mediaDir.existsSync()) return 0;

      var deletedCount = 0;
      await for (final entity in mediaDir.list()) {
        if (entity is! File) continue;
        final fileName = MediaService.sanitizeFileName(entity.path);
        if (!activeMedia.contains(fileName)) {
          try {
            await entity.delete();
            deletedCount++;
          } on Object {
            // Best-effort file deletion.
          }
        }
      }
      return deletedCount;
    } on Object {
      return 0;
    }
  }

  static Set<String> _descendantIds(
    List<Collection> collections,
    String parentId,
  ) {
    final result = <String>{};
    final pending = <String>[parentId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      for (final collection in collections) {
        if (collection.parentId == current && result.add(collection.id)) {
          pending.add(collection.id);
        }
      }
    }
    return result;
  }

  /// Duplicates a deck, including subdecks and cards when [deep] is true.
  static Future<List<Collection>> duplicateCollection(
    String collectionId, {
    bool deep = true,
  }) async {
    final source = _collectionsBox.get(collectionId);
    if (source == null) return const [];

    final allCollections = getAllCollections();
    final copied = <Collection>[];
    final idMap = <String, String>{};

    List<Collection> decksToCopy = [source];
    if (deep) {
      final descendantIds = _descendantIds(allCollections, collectionId);
      decksToCopy = [
        source,
        ...allCollections.where((deck) => descendantIds.contains(deck.id)),
      ];
    }

    for (final deck in decksToCopy) {
      idMap[deck.id] = newId();
    }

    for (final deck in decksToCopy) {
      copied.add(
        deck.copyWith(
          id: idMap[deck.id]!,
          name: deck.id == collectionId ? '${deck.name} (copy)' : deck.name,
          parentId: deck.id == collectionId
              ? source.parentId
              : idMap[deck.parentId] ?? source.parentId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    for (final deck in copied) {
      await _collectionsBox.put(deck.id, deck);
    }

    for (final deck in decksToCopy) {
      final newDeckId = idMap[deck.id]!;
      final cards = getCardsByCollection(deck.id, includeSubdecks: false);
      final grouped = <String, List<CardItem>>{};
      for (final card in cards) {
        grouped.putIfAbsent(card.noteKey, () => []).add(card);
      }
      for (final group in grouped.values) {
        final newNoteId = newId();
        for (final card in group) {
          final duplicate = _copyForNewNote(
            card,
            noteId: newNoteId,
            collectionId: newDeckId,
          );
          await _cardsBox.put(duplicate.id, duplicate);
        }
      }
    }

    await refreshCardCounts();
    return copied;
  }

  // ---------------------------------------------------------------------------
  // Cards
  // ---------------------------------------------------------------------------

  static List<CardItem> getAllCards() => _cardsBox.values.toList();

  static CardItem? getCard(String id) => _cardsBox.get(id);

  static List<CardItem> getCardsByCollection(
    String collectionId, {
    bool includeSubdecks = true,
  }) {
    if (!includeSubdecks) {
      return _cardsBox.values
          .where((card) => card.collectionId == collectionId)
          .toList();
    }
    final ids = _descendantIds(getAllCollections(), collectionId)
      ..add(collectionId);
    return _cardsBox.values
        .where((card) => ids.contains(card.collectionId))
        .toList();
  }

  static List<CardItem> getCardsForCollections(Iterable<String> ids) {
    final wanted = ids.toSet();
    return _cardsBox.values
        .where((card) => wanted.contains(card.collectionId))
        .toList();
  }

  static Future<CardItem> addCard(CardItem card) async {
    final normalized = card.noteId == null
        ? card.copyWith(noteId: card.id)
        : card;
    await _cardsBox.put(normalized.id, normalized);
    await refreshCardCounts();
    return normalized;
  }

  /// Returns all independently scheduled cards generated from the same note.
  static List<CardItem> getSiblings(CardItem card) {
    final noteKey = card.noteKey;
    return _cardsBox.values.where((item) => item.noteKey == noteKey).toList()
      ..sort((a, b) {
        final reverse = a.reverse.toString().compareTo(b.reverse.toString());
        if (reverse != 0) return reverse;
        return a.clozeIndex.compareTo(b.clozeIndex);
      });
  }

  static List<CardItem> getSiblingsByNoteId(String noteId) {
    return _cardsBox.values.where((item) => item.noteKey == noteId).toList()
      ..sort((a, b) => a.clozeIndex.compareTo(b.clozeIndex));
  }

  /// Creates or updates the complete note and all its sibling cards while
  /// preserving scheduling for identities that still exist.
  static Future<NoteSyncPlan> saveNote(CardItem edited) async {
    final existing = getSiblings(edited);
    final plan = const NoteService().plan(
      edited: edited,
      existing: existing,
      isNewNote: existing.isEmpty,
    );
    for (final card in plan.cards) {
      await _cardsBox.put(card.id, card);
    }
    for (final card in plan.removed) {
      await _cardsBox.delete(card.id);
    }
    await refreshCardCounts();
    return plan;
  }

  /// Deletes every sibling generated from a note, used by the note editor.
  static Future<List<CardItem>> deleteNote(CardItem card) async {
    final siblings = getSiblings(card);
    final removed = siblings.isEmpty
        ? [if (getCard(card.id) != null) getCard(card.id)!]
        : siblings;
    for (final item in removed) {
      await _cardsBox.delete(item.id);
      await TombstoneStore.add(SyncEntityType.card, item.id);
    }
    await refreshCardCounts();
    return removed;
  }

  static Future<void> updateCard(CardItem card) async {
    await _cardsBox.put(card.id, card);
  }

  static Future<void> saveCards(Iterable<CardItem> cards) async {
    final cardList = cards.toList();
    if (cardList.isEmpty) return;
    final map = <String, CardItem>{};
    for (final card in cardList) {
      final normalized =
          card.noteId == null ? card.copyWith(noteId: card.id) : card;
      map[normalized.id] = normalized;
    }
    await _cardsBox.putAll(map);
  }

  static Future<CardItem?> deleteCard(String id) async {
    final card = _cardsBox.get(id);
    if (card == null) return null;
    await _cardsBox.delete(id);
    await TombstoneStore.add(SyncEntityType.card, id);
    await refreshCardCounts();
    return card;
  }

  static Future<List<CardItem>> deleteCards(Iterable<String> ids) async {
    final removed = <CardItem>[];
    final idSet = ids.toSet();
    for (final id in idSet) {
      final card = _cardsBox.get(id);
      if (card != null) {
        removed.add(card);
      }
    }
    if (removed.isNotEmpty) {
      final cardIds = removed.map((c) => c.id).toList();
      await _cardsBox.deleteAll(cardIds);
      await TombstoneStore.addAll(SyncEntityType.card, cardIds);
      await refreshCardCounts();
    }
    return removed;
  }

  static Future<void> restoreCards(Iterable<CardItem> cards) async {
    final cardList = cards.toList();
    if (cardList.isEmpty) return;
    await _cardsBox.putAll({for (final card in cardList) card.id: card});
    await TombstoneStore.removeAll(
      SyncEntityType.card,
      cardList.map((c) => c.id),
    );
    await refreshCardCounts();
  }

  /// Deletes only the deck record, without cascading, for sync apply.
  static Future<void> deleteCollectionRecord(String id) async {
    await _collectionsBox.delete(id);
    await TombstoneStore.add(SyncEntityType.collection, id);
  }

  /// Duplicates the complete note group. Callers duplicating a sibling get the
  /// same set of independently scheduled cards as the original.
  static Future<List<CardItem>> duplicateNote(CardItem card) async {
    final siblings = getSiblings(card);
    if (siblings.isEmpty) return const [];
    final newNoteId = newId();
    final copies = [
      for (final item in siblings) _copyForNewNote(item, noteId: newNoteId),
    ];
    for (final copy in copies) {
      await _cardsBox.put(copy.id, copy);
    }
    await refreshCardCounts();
    return copies;
  }

  static Future<List<CardItem>> duplicateCards(Iterable<String> ids) async {
    final seenNotes = <String>{};
    final copies = <CardItem>[];
    for (final id in ids) {
      final card = _cardsBox.get(id);
      if (card == null || !seenNotes.add(card.noteKey)) continue;
      final siblings = getSiblings(card);
      final newNoteId = newId();
      for (final item in siblings) {
        final copy = _copyForNewNote(item, noteId: newNoteId);
        copies.add(copy);
        await _cardsBox.put(copy.id, copy);
      }
    }
    if (copies.isNotEmpty) await refreshCardCounts();
    return copies;
  }

  static Future<CardItem> duplicateCard(String id) async {
    final source = _cardsBox.get(id);
    if (source == null) throw StateError('Card not found');
    final copies = await duplicateNote(source);
    if (copies.isEmpty) throw StateError('Card not found');
    return copies.first;
  }

  static CardItem _copyForNewNote(
    CardItem source, {
    required String noteId,
    String? collectionId,
  }) {
    return CardItem(
      frontText: source.frontText,
      backText: source.backText,
      collectionId: collectionId ?? source.collectionId,
      createdAt: DateTime.now(),
      type: source.type,
      tags: List<String>.from(source.tags),
      imagePath: source.imagePath,
      audioPath: source.audioPath,
      noteId: noteId,
      reverse: source.reverse,
      clozeIndex: source.clozeIndex,
    );
  }

  static Future<void> moveCards(
    Iterable<String> ids,
    String targetCollectionId,
  ) async {
    if (_collectionsBox.get(targetCollectionId) == null) {
      throw ArgumentError('Target deck does not exist');
    }
    final cardsToMove = <String, CardItem>{};
    for (final id in ids) {
      final card = _cardsBox.get(id);
      if (card == null) continue;
      for (final sibling in getSiblings(card)) {
        cardsToMove[sibling.id] = sibling;
      }
    }
    for (final card in cardsToMove.values) {
      await _cardsBox.put(
        card.id,
        card.copyWith(
          collectionId: targetCollectionId,
          updatedAt: DateTime.now(),
        ),
      );
    }
    await refreshCardCounts();
  }

  /// Keeps the legacy `cardCount` field in sync for older UI surfaces.
  static Future<void> refreshCardCounts() async {
    final cards = getAllCards();
    final collections = getAllCollections();
    final collectionsById = {for (final deck in collections) deck.id: deck};
    final counts = <String, int>{};
    for (final card in cards) {
      final visited = <String>{};
      var deckId = card.collectionId;
      while (visited.add(deckId)) {
        counts[deckId] = (counts[deckId] ?? 0) + 1;
        final parentId = collectionsById[deckId]?.parentId;
        if (parentId == null || parentId.isEmpty) break;
        deckId = parentId;
      }
    }
    for (final collection in collections) {
      final count = counts[collection.id] ?? 0;
      if (collection.cardCount != count) {
        await _collectionsBox.put(
          collection.id,
          collection.copyWith(cardCount: count),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Review logs
  // ---------------------------------------------------------------------------

  static List<ReviewLog> getAllLogs() => _logsBox.values.toList();

  /// Retrieves only today's review logs. Because Hive holds opened box values in
  /// memory, iterating `_logsBox.values` takes < 1ms even across 10,000+ entries,
  /// while ensuring 100% accuracy regardless of UUID key ordering or out-of-order syncs.
  static List<ReviewLog> getTodayLogs(DateTime now) {
    if (_logsBox.isEmpty) return const [];
    final startOfDay = DateTime(now.year, now.month, now.day);
    final todayLogs = <ReviewLog>[];
    for (final log in _logsBox.values) {
      if (!log.reviewedAt.isBefore(startOfDay)) {
        todayLogs.add(log);
      }
    }
    return todayLogs;
  }

  static List<ReviewLog> getLogsForCard(String cardId) =>
      _logsBox.values.where((log) => log.cardId == cardId).toList();

  static Future<ReviewLog> addLog(ReviewLog log) async {
    await _logsBox.put(log.id, log);
    return log;
  }

  static Future<void> addLogs(Iterable<ReviewLog> logs) async {
    for (final log in logs) {
      await _logsBox.put(log.id, log);
    }
  }

  static Future<ReviewLog?> deleteLog(String id) async {
    final log = _logsBox.get(id);
    if (log == null) return null;
    await _logsBox.delete(id);
    return log;
  }

  /// Restores a card snapshot and removes the matching review log atomically
  /// enough for UI undo (log removal is idempotent).
  static Future<void> undoReview(CardItem previousCard, String logId) async {
    await _cardsBox.put(previousCard.id, previousCard);
    await _logsBox.delete(logId);
  }

  // ---------------------------------------------------------------------------
  // Maintenance
  // ---------------------------------------------------------------------------

  static Future<void> replaceAll({
    required Iterable<Collection> collections,
    required Iterable<CardItem> cards,
    required Iterable<ReviewLog> logs,
  }) async {
    final collectionList = collections.toList();
    final cardList = cards.toList();
    final logList = logs.toList();

    // Write first, delete stale keys afterwards: a crash mid-restore must never
    // leave the database empty.
    for (final collection in collectionList) {
      await _collectionsBox.put(collection.id, collection);
    }
    for (final card in cardList) {
      await _cardsBox.put(card.id, card);
    }
    for (final log in logList) {
      await _logsBox.put(log.id, log);
    }

    final collectionIds = collectionList.map((deck) => deck.id).toSet();
    final cardIds = cardList.map((card) => card.id).toSet();
    final logIds = logList.map((log) => log.id).toSet();
    for (final key in _collectionsBox.keys.toList()) {
      if (!collectionIds.contains(key)) await _collectionsBox.delete(key);
    }
    for (final key in _cardsBox.keys.toList()) {
      if (!cardIds.contains(key)) await _cardsBox.delete(key);
    }
    for (final key in _logsBox.keys.toList()) {
      if (!logIds.contains(key)) await _logsBox.delete(key);
    }
    await refreshCardCounts();
    await TombstoneStore.clear();
  }

  static Future<void> clearAllData() async {
    await _collectionsBox.clear();
    await _cardsBox.clear();
    await _logsBox.clear();
    await TombstoneStore.clear();
  }

  /// Re-runs the idempotent repair pass. Exposed for diagnostics and tests; the
  /// normal app runs it automatically during startup.
  static Future<void> repairDatabase() async {
    await _migrate();
  }

  static Future<void> close() async {
    await _cardsBox.close();
    await _collectionsBox.close();
    await _logsBox.close();
    await _metaBox.close();
    await _syncBox.close();
    _initialized = false;
  }

  @visibleForTesting
  static bool get isInitialized => _initialized;
}
