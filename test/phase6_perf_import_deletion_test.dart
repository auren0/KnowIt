import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/services/anki/apkg_importer.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/media_service.dart';
import 'package:knowit/services/study_queue_service.dart';
import 'package:knowit/services/sync/tombstone_store.dart';
import 'package:knowit/utils/import_progress.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempRoot;

  setUpAll(() async {
    await initTestHive();
    tempRoot = await Directory.systemTemp.createTemp('knowit_phase6_test_');
    MediaService.documentsDirectoryOverride = tempRoot;
  });

  setUp(() async {
    await initTestHive();
    await HiveService.clearAllData();
  });

  tearDownAll(() async {
    MediaService.documentsDirectoryOverride = null;
    try {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    } catch (_) {}
    await closeTestHive();
  });

  group('Phase 6: Part 1 & 4 — Instant Deck and Nested Deck Deletion Benchmarks', () {
    test('benchmarks deletion of small deck (100 cards)', () async {
      final deck = Collection(
        id: 'deck-100',
        name: 'Small Deck',
        emoji: '📘',
        colorValue: 0xFFFFC107,
      );
      await HiveService.createCollection(deck);

      final cards = List.generate(
        100,
        (i) => CardItem(
          id: 'card-100-$i',
          frontText: 'Front $i',
          backText: 'Back $i',
          collectionId: deck.id,
        ),
      );
      await HiveService.saveCards(cards);

      final sw = Stopwatch()..start();
      final snapshot = await HiveService.deleteCollectionCascade(deck.id);
      sw.stop();

      expect(snapshot, isNotNull);
      expect(snapshot!.cards.length, 100);
      expect(HiveService.getCollection(deck.id), isNull);
      expect(HiveService.getCardsByCollection(deck.id), isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(100)); // Instant
    });

    test('benchmarks deletion of medium deck (1,000 cards) & undo', () async {
      final deck = Collection(
        id: 'deck-1000',
        name: 'Medium Deck',
        emoji: '📗',
        colorValue: 0xFFFFC107,
      );
      await HiveService.createCollection(deck);

      final cards = List.generate(
        1000,
        (i) => CardItem(
          id: 'card-1000-$i',
          frontText: 'Front $i',
          backText: 'Back $i',
          collectionId: deck.id,
        ),
      );
      await HiveService.saveCards(cards);

      final swDelete = Stopwatch()..start();
      final snapshot = await HiveService.deleteCollectionCascade(deck.id);
      swDelete.stop();

      expect(snapshot, isNotNull);
      expect(snapshot!.cards.length, 1000);
      expect(HiveService.getCollection(deck.id), isNull);
      expect(HiveService.getCardsByCollection(deck.id), isEmpty);
      expect(swDelete.elapsedMilliseconds, lessThan(150));

      // Test batched restore
      final swRestore = Stopwatch()..start();
      await HiveService.restoreDeckSnapshot(snapshot);
      swRestore.stop();

      expect(HiveService.getCollection(deck.id), isNotNull);
      expect(HiveService.getCardsByCollection(deck.id).length, 1000);
      expect(swRestore.elapsedMilliseconds, lessThan(150));
    });

    test('benchmarks large deck (5,000 cards) + 10,000 review logs deletion', () async {
      final deck = Collection(
        id: 'deck-5000',
        name: 'Large Deck',
        emoji: '📙',
        colorValue: 0xFFFFC107,
      );
      await HiveService.createCollection(deck);

      final cards = List.generate(
        5000,
        (i) => CardItem(
          id: 'card-5000-$i',
          frontText: 'Front $i',
          backText: 'Back $i',
          collectionId: deck.id,
        ),
      );
      await HiveService.saveCards(cards);

      final now = DateTime.now();
      final logs = List.generate(
        10000,
        (i) => ReviewLog(
          id: 'log-5000-$i',
          cardId: 'card-5000-${i % 5000}',
          collectionId: deck.id,
          rating: 3,
          reviewedAt: now.subtract(Duration(minutes: i)),
          previousState: 2,
          scheduledDays: 4,
          mode: 'srs',
        ),
      );
      await HiveService.addLogs(logs);

      final sw = Stopwatch()..start();
      final snapshot = await HiveService.deleteCollectionCascade(deck.id);
      sw.stop();

      expect(snapshot, isNotNull);
      expect(snapshot!.cards.length, 5000);
      expect(snapshot.logs.length, 10000);
      expect(HiveService.getCollection(deck.id), isNull);
      expect(HiveService.getCardsByCollection(deck.id), isEmpty);
      // Batched delete must complete smoothly well under 250ms even with 15,000 combined records
      expect(sw.elapsedMilliseconds, lessThan(250));

      // Verify tombstones
      expect(TombstoneStore.get(SyncEntityType.collection, deck.id), isNotNull);
      expect(TombstoneStore.get(SyncEntityType.card, 'card-5000-0'), isNotNull);
      expect(TombstoneStore.get(SyncEntityType.card, 'card-5000-4999'), isNotNull);
    });

    test('benchmarks nested deck hierarchy (4 levels) deletion', () async {
      final root = Collection(id: 'root', name: 'Root', emoji: '🌳', colorValue: 0xFF000000);
      final l1 = Collection(id: 'l1', name: 'Level 1', parentId: 'root', emoji: '🌿', colorValue: 0xFF000000);
      final l2 = Collection(id: 'l2', name: 'Level 2', parentId: 'l1', emoji: '🍃', colorValue: 0xFF000000);
      final l3 = Collection(id: 'l3', name: 'Level 3', parentId: 'l2', emoji: '🌱', colorValue: 0xFF000000);

      await HiveService.createCollection(root);
      await HiveService.createCollection(l1);
      await HiveService.createCollection(l2);
      await HiveService.createCollection(l3);

      final cards = <CardItem>[
        for (var i = 0; i < 200; i++) CardItem(id: 'r-$i', frontText: 'q', backText: 'a', collectionId: 'root'),
        for (var i = 0; i < 200; i++) CardItem(id: 'l1-$i', frontText: 'q', backText: 'a', collectionId: 'l1'),
        for (var i = 0; i < 200; i++) CardItem(id: 'l2-$i', frontText: 'q', backText: 'a', collectionId: 'l2'),
        for (var i = 0; i < 200; i++) CardItem(id: 'l3-$i', frontText: 'q', backText: 'a', collectionId: 'l3'),
      ];
      await HiveService.saveCards(cards);

      final sw = Stopwatch()..start();
      final snapshot = await HiveService.deleteCollectionCascade('root');
      sw.stop();

      expect(snapshot, isNotNull);
      expect(snapshot!.subdecks.length, 3);
      expect(snapshot.cards.length, 800);
      expect(HiveService.getCollection('root'), isNull);
      expect(HiveService.getCollection('l1'), isNull);
      expect(HiveService.getCollection('l2'), isNull);
      expect(HiveService.getCollection('l3'), isNull);
      expect(HiveService.getAllCards(), isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(100));
    });

    test('study queue excludes deleted cards immediately', () async {
      final deck = Collection(id: 'deck-queue', name: 'Queue Deck', emoji: '🎯', colorValue: 0xFF);
      await HiveService.createCollection(deck);

      final card = CardItem(
        id: 'card-q1',
        frontText: 'Question',
        backText: 'Answer',
        collectionId: deck.id,
      );
      await HiveService.saveCards([card]);

      // Before deletion, queue includes the card
      final queueBefore = const StudyQueueService().build(
        cards: HiveService.getAllCards(),
        mode: StudyMode.srs,
        settings: const AppSettings(),
        logs: const [],
        now: DateTime.now(),
      );
      expect(queueBefore.cards.any((c) => c.id == card.id), isTrue);

      // Delete deck
      await HiveService.deleteCollectionCascade(deck.id);

      // After deletion, queue excludes the card
      final queueAfter = const StudyQueueService().build(
        cards: HiveService.getAllCards(),
        mode: StudyMode.srs,
        settings: const AppSettings(),
        logs: const [],
        now: DateTime.now(),
      );
      expect(queueAfter.cards.any((c) => c.id == card.id), isFalse);
    });
  });

  group('Phase 6: Part 2 — Non-Blocking APKG Import & Batched Writes', () {
    test('parses and imports APKG package with background isolate and batched writes', () async {
      final bytes = await _buildMultiNoteApkgFixture(100);

      final previewStopwatch = Stopwatch()..start();
      const importer = AnkiImportService();
      final fractions = <double>[];

      final preview = await importer.previewBytes(
        bytes,
        fileName: 'bench_100.apkg',
        onProgress: (p) {
          if (p.fraction != null) fractions.add(p.fraction!);
        },
      );
      previewStopwatch.stop();

      expect(preview.notes.length, 100);
      expect(previewStopwatch.elapsedMilliseconds, lessThan(3000));
      expect(fractions, isNotEmpty);

      // Commit benchmark
      final commitStopwatch = Stopwatch()..start();
      final commitFractions = <double>[];
      final result = await importer.commit(
        preview,
        onProgress: (p) {
          if (p.fraction != null) commitFractions.add(p.fraction!);
        },
      );
      commitStopwatch.stop();

      expect(result.importedNotes, 100);
      expect(commitStopwatch.elapsedMilliseconds, lessThan(2000));
      expect(commitFractions, isNotEmpty);
      expect(commitFractions.last, 1.0);
    });

    test('supports instant cancellation during APKG preview', () async {
      final bytes = await _buildMultiNoteApkgFixture(50);
      const importer = AnkiImportService();

      final token = ImportCancellationToken()..cancel(); // Pre-cancelled
      expect(
        () => importer.previewBytes(bytes, cancellationToken: token),
        throwsA(isA<ImportCancelledException>()),
      );
    });
  });

  group('Phase 6: Part 3 — Two-Phase Deletion & Orphan Media Cleanup', () {
    test('cleans up orphaned media while strictly preserving shared media', () async {
      final sampleAudio = Uint8List.fromList([255, 251, 144, 100, 10, 20, 30]);
      final sampleImage = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

      final exclusivePath = await MediaService.storeBytes(
        bytes: sampleAudio,
        fileName: 'exclusive_audio.mp3',
      );
      final sharedPath = await MediaService.storeBytes(
        bytes: sampleImage,
        fileName: 'shared_diagram.png',
      );
      expect(exclusivePath, isNotNull);
      expect(sharedPath, isNotNull);

      final deckA = Collection(id: 'deck-a', name: 'Deck A', emoji: 'A', colorValue: 0xFF);
      final deckB = Collection(id: 'deck-b', name: 'Deck B', emoji: 'B', colorValue: 0xFF);
      await HiveService.createCollection(deckA);
      await HiveService.createCollection(deckB);

      // Card in Deck A references exclusiveAudio and sharedDiagram
      final cardA = CardItem(
        id: 'card-a',
        frontText: 'Card A',
        backText: 'Back A',
        collectionId: deckA.id,
        audioPath: exclusivePath,
        imagePath: sharedPath,
      );
      // Card in Deck B also references sharedDiagram
      final cardB = CardItem(
        id: 'card-b',
        frontText: 'Card B',
        backText: 'Back B',
        collectionId: deckB.id,
        imagePath: sharedPath,
      );
      await HiveService.saveCards([cardA, cardB]);

      // Phase A: Delete Deck A
      await HiveService.deleteCollectionCascade(deckA.id);
      expect(HiveService.getCollection(deckA.id), isNull);

      // Phase B: Run background orphan media cleanup
      final deletedCount = await HiveService.cleanupOrphanedMedia();
      expect(deletedCount, 1); // exclusive_audio.mp3 was deleted

      // Verify exclusive audio was deleted from disk
      expect(File(exclusivePath!).existsSync(), isFalse);

      // Verify shared diagram was PRESERVED because Deck B still references it
      expect(File(sharedPath!).existsSync(), isTrue);
    });
  });

  group('Phase 6: Part 5 — Progress Throttling and UI Rebuild Reduction', () {
    test('ProgressThrottler rate-limits notifications while preserving milestones', () async {
      final emitted = <ImportProgress>[];
      final throttler = ProgressThrottler(
        interval: const Duration(milliseconds: 60),
        onProgress: (p) => emitted.add(p),
      );

      // Rapidly fire 100 progress updates in the same millisecond
      for (var i = 0; i < 100; i++) {
        throttler.report(i / 100.0, 'Processing cards…', '($i / 100)');
      }

      // Initial update was emitted, intermediate burst was throttled
      expect(emitted.length, lessThan(5));

      // Stage change must emit immediately regardless of interval
      throttler.report(0.99, 'New Stage');
      expect(emitted.last.stage, 'New Stage');

      // 1.0 complete must emit immediately
      throttler.report(1.0, 'Complete');
      expect(emitted.last.fraction, 1.0);
    });
  });
}

Future<Uint8List> _buildMultiNoteApkgFixture(int noteCount) async {
  final directory = await Directory.systemTemp.createTemp('knowit_bench_apkg_');
  final dbFile = File('${directory.path}/collection.anki2');
  final db = sqlite3.open(dbFile.path);

  db.execute('''
    CREATE TABLE col (id integer primary key, crt integer, mod integer,
      scm integer, ver integer, dty integer, usn integer, ls integer,
      conf text, models text, decks text, dconf text, tags text)
  ''');
  db.execute('''
    CREATE TABLE notes (id integer primary key, guid text, mid integer,
      mod integer, usn integer, tags text, flds text, sfld integer,
      csum integer, flags integer, data text)
  ''');
  db.execute('''
    CREATE TABLE cards (id integer primary key, nid integer, did integer,
      ord integer, mod integer, usn integer, type integer, queue integer,
      due integer, ivl integer, factor integer, reps integer, lapses integer,
      left integer, odue integer, odid integer, flags integer, data text)
  ''');

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final models = {
    '1': {
      'id': 1,
      'name': 'Basic',
      'type': 0,
      'tmpls': [{'ord': 0}],
    },
  };
  final decks = {'1': {'id': 1, 'name': 'Benchmark Deck'}};

  db.execute(
    'INSERT INTO col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, decks, dconf, tags) '
    'VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, ?)',
    [now, now, now, '{}', jsonEncode(models), jsonEncode(decks), '{}', '{}'],
  );

  for (var i = 0; i < noteCount; i++) {
    db.execute(
      'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) '
      'VALUES (?, ?, 1, ?, -1, \'\', ?, 0, 0, 0, \'\')',
      [i + 1, 'g$i', now, 'Front Question $i\x1fBack Answer $i'],
    );
    db.execute(
      'INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data) '
      'VALUES (?, ?, 1, 0, ?, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \'\')',
      [i + 1, i + 1, now],
    );
  }

  db.close();
  final dbBytes = await dbFile.readAsBytes();

  final archive = Archive();
  archive.addFile(ArchiveFile('collection.anki2', dbBytes.length, dbBytes));
  final mediaJson = utf8.encode('{}');
  archive.addFile(ArchiveFile('media', mediaJson.length, mediaJson));

  final encoded = ZipEncoder().encode(archive);
  try {
    directory.deleteSync(recursive: true);
  } catch (_) {}
  return Uint8List.fromList(encoded);
}
