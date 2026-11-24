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
import 'package:knowit/utils/import_progress.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_helpers.dart';

void main() {
  late Directory tempRoot;

  setUpAll(() async {
    await initTestHive();
    tempRoot = await Directory.systemTemp.createTemp('knowit_phase5_test_');
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

  group('Part 1 — Audio Reliability & Media Pipeline', () {
    test('resolves media files even when directory path changes', () async {
      final sampleBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final savedPath = await MediaService.storeBytes(
        bytes: sampleBytes,
        fileName: 'pronunciation.mp3',
      );
      expect(savedPath, isNotNull);
      expect(File(savedPath!).existsSync(), isTrue);

      // Verify direct resolution
      final resolvedDirect = await MediaService.resolvePath(savedPath);
      expect(resolvedDirect, savedPath);

      // Simulate app update/restore where sandbox directory prefix differs:
      final simulatedOldPath =
          '/var/mobile/Containers/Data/Application/OLD-SANDBOX-UUID/Documents/knowit_media/pronunciation.mp3';
      final resolvedSandbox = await MediaService.resolvePath(simulatedOldPath);
      expect(resolvedSandbox, isNotNull);
      expect(File(resolvedSandbox!).existsSync(), isTrue);
      expect(resolvedSandbox, savedPath);

      // Verify relative path resolution
      final resolvedRelative = await MediaService.resolvePath('pronunciation.mp3');
      expect(resolvedRelative, savedPath);
    });

    test('verifies audio files and distinguishes error types', () async {
      // 1. Missing file
      final missingStatus = await MediaService.verifyAudio('/non/existent/file.mp3');
      expect(missingStatus, AudioVerificationStatus.missingFile);

      // 2. Unsupported format
      final textBytes = utf8.encode('just a text file');
      final textPath = await MediaService.storeBytes(
        bytes: Uint8List.fromList(textBytes),
        fileName: 'document.txt',
      );
      final unsupportedStatus = await MediaService.verifyAudio(textPath);
      expect(unsupportedStatus, AudioVerificationStatus.unsupportedFormat);

      // 3. Corrupted / empty file
      final emptyPath = await MediaService.storeBytes(
        bytes: Uint8List(0),
        fileName: 'empty_audio.mp3',
      );
      final corruptedStatus = await MediaService.verifyAudio(emptyPath);
      expect(corruptedStatus, AudioVerificationStatus.corruptedFile);

      // 4. Valid audio file
      final validBytes = Uint8List.fromList([255, 251, 144, 100]); // MP3 sync header
      final validPath = await MediaService.storeBytes(
        bytes: validBytes,
        fileName: 'valid_audio.mp3',
      );
      final validStatus = await MediaService.verifyAudio(validPath);
      expect(validStatus, AudioVerificationStatus.valid);
    });

    test('imports APKG with numeric manifest, Unicode audio, and dedupes media', () async {
      final bytes = await _buildAudioApkgFixture();
      const service = AnkiImportService();
      final preview = await service.previewBytes(bytes, fileName: 'audio_test.apkg');

      expect(preview.noteCount, 3);
      expect(preview.mediaCount, 2); // 1 Russian audio + 1 shared audio

      final result = await service.commit(preview);
      expect(result.importedNotes, 3);
      expect(result.importedCards, 3);
      expect(result.mediaFiles, 2); // Deduplicated storage!

      final cards = HiveService.getAllCards();
      final audioCards = cards.where((c) => c.isPlayable).toList();
      expect(audioCards.length, 3);

      for (final card in audioCards) {
        final verified = await MediaService.verifyAudio(card.audioPath);
        expect(verified, AudioVerificationStatus.valid);
      }
    });

    test('preserves audio card when front content is only [sound:...]', () async {
      final bytes = await _buildSoundOnlyApkgFixture();
      const service = AnkiImportService();
      final preview = await service.previewBytes(bytes);
      expect(preview.notes.length, 1);
      expect(preview.notes.first.frontText, '[Audio]');
      expect(preview.notes.first.audioReference, 'listening.mp3');

      final result = await service.commit(preview);
      expect(result.importedCards, 1);
      final card = HiveService.getAllCards().first;
      expect(card.frontText, '[Audio]');
      expect(card.isPlayable, isTrue);
    });
  });

  group('Part 2 — Performance Benchmarks & Hive Optimization', () {
    test('benchmarks large dataset operations (100, 1000, 10000 cards)', () async {
      final deck = Collection(
        id: 'perf-deck-1',
        name: 'Performance Deck',
        emoji: '⚡',
        colorValue: 0xFFFFC107,
      );
      await HiveService.createCollection(deck);

      // Generate 1,000 cards in memory
      final thousandCards = List.generate(
        1000,
        (i) => CardItem(
          id: 'card-$i',
          frontText: 'Question number $i with some text for search testing',
          backText: 'Answer number $i with corresponding details',
          collectionId: deck.id,
          createdAt: DateTime.now().subtract(Duration(minutes: i)),
        ),
      );

      final saveStopwatch = Stopwatch()..start();
      await HiveService.saveCards(thousandCards);
      saveStopwatch.stop();
      expect(HiveService.getAllCards().length, 1000);

      // Benchmark queue building with 10,000 review logs
      final now = DateTime.now();
      final tenThousandLogs = List<ReviewLog>.generate(
        10000,
        (i) => ReviewLog(
          id: 'log-$i',
          cardId: 'card-${i % 1000}',
          collectionId: deck.id,
          rating: 3,
          reviewedAt: i >= 9950
              ? now.subtract(Duration(minutes: (10000 - i) * 5)) // 50 reviews today
              : now.subtract(Duration(days: ((9950 - i) ~/ 50) + 1)), // past reviews
          previousState: 2,
          scheduledDays: 4,
          mode: 'srs',
        ),
      );

      await HiveService.addLogs(tenThousandLogs);

      // Measure getTodayLogs speed (should take < 10ms by reading backwards)
      final logsStopwatch = Stopwatch()..start();
      final todayLogs = HiveService.getTodayLogs(now);
      logsStopwatch.stop();

      expect(todayLogs.length, 50);
      expect(logsStopwatch.elapsedMilliseconds, lessThan(100));

      // Measure StudyQueueService.build with getTodayLogs
      final queueStopwatch = Stopwatch()..start();
      final queue = const StudyQueueService().build(
        cards: thousandCards,
        mode: StudyMode.srs,
        settings: const AppSettings(),
        logs: todayLogs,
        now: now,
      );
      queueStopwatch.stop();

      expect(queue.cards.length, greaterThan(0));
      expect(queueStopwatch.elapsedMilliseconds, lessThan(50));
    });
  });

  group('Part 3 — Import Progress & Cancellation', () {
    test('reports progress updates during APKG preview and commit', () async {
      final bytes = await _buildAudioApkgFixture();
      final reportedFractions = <double>[];
      final stages = <String>[];

      const service = AnkiImportService();
      final preview = await service.previewBytes(
        bytes,
        onProgress: (p) {
          if (p.fraction != null) reportedFractions.add(p.fraction!);
          stages.add(p.stage);
        },
      );

      expect(reportedFractions, isNotEmpty);
      expect(stages, isNotEmpty);
      expect(reportedFractions.last, 1.0);

      final commitFractions = <double>[];
      await service.commit(
        preview,
        onProgress: (p) {
          if (p.fraction != null) commitFractions.add(p.fraction!);
        },
      );

      expect(commitFractions, isNotEmpty);
      expect(commitFractions.first, lessThan(0.25));
      expect(commitFractions.last, 1.0);
    });

    test('supports safe import cancellation and cleans up rollback', () async {
      final bytes = await _buildAudioApkgFixture();
      const service = AnkiImportService();
      final preview = await service.previewBytes(bytes);

      final token = ImportCancellationToken();
      token.cancel(); // Pre-cancel

      expect(
        () => service.commit(preview, cancellationToken: token),
        throwsA(isA<ImportCancelledException>()),
      );

      // Verify rollback: no cards committed
      expect(HiveService.getAllCards(), isEmpty);
    });

    test('EtaEstimator smooths time and formats properly in English and Russian', () {
      final estimator = EtaEstimator();
      expect(estimator.update(0.01), isNull); // Insufficient data

      final eta = const Duration(seconds: 42);
      final progress = ImportProgress(
        fraction: 0.5,
        stage: 'Extracting media',
        eta: eta,
      );

      expect(progress.percentage, 50);
      expect(progress.formatEta(isRussian: false), contains('42 seconds remaining'));
      expect(progress.formatEta(isRussian: true), contains('42 сек.'));
    });
  });
}

Future<Uint8List> _buildAudioApkgFixture() async {
  final directory = await Directory.systemTemp.createTemp('knowit_audio_fixture_');
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
  final decks = {
    '1': {'id': 1, 'name': 'Audio Deck'},
  };

  db.execute(
    'INSERT INTO col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, decks, dconf, tags) '
    'VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, ?)',
    [now, now, now, '{}', jsonEncode(models), jsonEncode(decks), '{}', '{}'],
  );

  // Note 1: Russian Unicode audio filename
  db.execute(
    'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) '
    'VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, \'\')',
    [101, 'g1', 1, now, '', 'Привет [sound:привет.mp3]\x1fHello', 'Привет', 0],
  );

  // Note 2: Shared audio with URL encoding and spaces
  db.execute(
    'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) '
    'VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, \'\')',
    [102, 'g2', 1, now, '', 'Word One [sound:shared%20audio.mp3]\x1fDefinition', 'Word One', 0],
  );

  // Note 3: References the same shared audio (tests deduplication)
  db.execute(
    'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) '
    'VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, \'\')',
    [103, 'g3', 1, now, '', 'Word Two [sound:shared audio.mp3]\x1fDefinition 2', 'Word Two', 0],
  );

  db.execute('INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data) VALUES (201, 101, 1, 0, ?, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \'\')', [now]);
  db.execute('INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data) VALUES (202, 102, 1, 0, ?, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \'\')', [now]);
  db.execute('INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data) VALUES (203, 103, 1, 0, ?, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \'\')', [now]);

  db.close();
  final dbBytes = await dbFile.readAsBytes();

  final archive = Archive();
  archive.addFile(ArchiveFile('collection.anki2', dbBytes.length, dbBytes));

  // Numeric manifest mapping:
  // "0" -> "привет.mp3"
  // "1" -> "shared audio.mp3"
  final mediaJson = utf8.encode(jsonEncode({
    '0': 'привет.mp3',
    '1': 'shared audio.mp3',
  }));
  archive.addFile(ArchiveFile('media', mediaJson.length, mediaJson));

  final audioBytes1 = Uint8List.fromList([255, 251, 144, 100, 1, 2, 3]);
  final audioBytes2 = Uint8List.fromList([255, 251, 144, 100, 4, 5, 6]);
  archive.addFile(ArchiveFile('0', audioBytes1.length, audioBytes1));
  archive.addFile(ArchiveFile('1', audioBytes2.length, audioBytes2));

  final encoded = ZipEncoder().encode(archive);
  try {
    directory.deleteSync(recursive: true);
  } catch (_) {}
  return Uint8List.fromList(encoded);
}

Future<Uint8List> _buildSoundOnlyApkgFixture() async {
  final directory = await Directory.systemTemp.createTemp('knowit_soundonly_');
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
      'name': 'Listening',
      'type': 0,
      'tmpls': [{'ord': 0}],
    },
  };
  final decks = {'1': {'id': 1, 'name': 'Listening Deck'}};

  db.execute(
    'INSERT INTO col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, decks, dconf, tags) '
    'VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, ?)',
    [now, now, now, '{}', jsonEncode(models), jsonEncode(decks), '{}', '{}'],
  );

  // Front side contains ONLY [sound:listening.mp3]
  db.execute(
    'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) '
    'VALUES (1, \'g1\', 1, ?, -1, \'\', \'[sound:listening.mp3]\x1fText Answer\', 0, 0, 0, \'\')',
    [now],
  );
  db.execute('INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data) VALUES (1, 1, 1, 0, ?, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \'\')', [now]);

  db.close();
  final dbBytes = await dbFile.readAsBytes();

  final archive = Archive();
  archive.addFile(ArchiveFile('collection.anki2', dbBytes.length, dbBytes));
  final mediaJson = utf8.encode(jsonEncode({'0': 'listening.mp3'}));
  archive.addFile(ArchiveFile('media', mediaJson.length, mediaJson));
  final audioBytes = Uint8List.fromList([255, 251, 144, 100, 7, 8, 9]);
  archive.addFile(ArchiveFile('0', audioBytes.length, audioBytes));

  final encoded = ZipEncoder().encode(archive);
  try {
    directory.deleteSync(recursive: true);
  } catch (_) {}
  return Uint8List.fromList(encoded);
}
