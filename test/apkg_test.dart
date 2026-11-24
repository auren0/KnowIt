import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/services/anki/apkg_exporter.dart';
import 'package:knowit/services/anki/apkg_importer.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/media_service.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_helpers.dart';

void main() {
  late Directory mediaRoot;

  setUpAll(() async {
    await initTestHive();
    mediaRoot = await Directory.systemTemp.createTemp('knowit_apkg_media_');
    MediaService.documentsDirectoryOverride = mediaRoot;
  });

  setUp(initTestHive);

  tearDownAll(() async {
    MediaService.documentsDirectoryOverride = null;
    try {
      if (mediaRoot.existsSync()) mediaRoot.deleteSync(recursive: true);
    } on Object {
      // Best effort.
    }
    await closeTestHive();
  });

  test('imports a classic APKG with decks, types, tags and media', () async {
    final bytes = await _buildFixturePackage();
    const service = AnkiImportService();
    final preview = await service.previewBytes(bytes, fileName: 'sample.apkg');

    expect(preview.noteCount, 3);
    expect(preview.generatedCardCount, 5);
    expect(preview.deckNames.length, greaterThanOrEqualTo(2));
    expect(preview.mediaCount, 1);
    expect(preview.warnings.join(' '), contains('scheduling history'));

    final result = await service.commit(preview);

    expect(result.importedNotes, 3);
    expect(result.importedCards, 5);
    expect(result.mediaFiles, 1);
    final cards = HiveService.getAllCards();
    expect(cards.length, 5);
    expect(cards.where((card) => card.type == CardType.reversed).length, 2);
    expect(cards.where((card) => card.isCloze).length, 2);
    expect(cards.any((card) => card.tags.contains('language')), isTrue);
    final withImage = cards.where((card) => card.hasImage).toList();
    expect(withImage.length, 1);
    expect(File(withImage.single.imagePath!).existsSync(), isTrue);
    expect(
      HiveService.getAllCollections().any((deck) => deck.name == 'Child'),
      isTrue,
    );
    final parentDeck = HiveService.getAllCollections().firstWhere(
      (deck) => deck.name == 'Parent',
    );
    final childDeck = HiveService.getAllCollections().firstWhere(
      (deck) => deck.name == 'Child',
    );
    expect(childDeck.parentId, parentDeck.id);

    final again = await service.commit(preview);
    expect(again.skippedDuplicates, 3);
    expect(HiveService.getAllCards().length, 5);
  });

  test(
    'rejects malformed archives and unsupported compressed collections',
    () async {
      const service = AnkiImportService();
      await expectLater(
        service.previewBytes(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<AnkiFormatException>()),
      );

      final archive = Archive();
      final fake = utf8.encode('not a database');
      archive.addFile(ArchiveFile('collection.anki21b', fake.length, fake));
      final encoded = ZipEncoder().encode(archive);
      await expectLater(
        service.previewBytes(Uint8List.fromList(encoded)),
        throwsA(
          isA<AnkiFormatException>().having(
            (error) => error.message,
            'message',
            contains('zstd-compressed'),
          ),
        ),
      );
    },
  );

  test('export builds a structurally valid APKG and round-trips', () async {
    final parent = makeDeck(name: 'Languages');
    final child = makeDeck(name: 'French', parentId: parent.id);
    await HiveService.createCollection(parent);
    await HiveService.createCollection(child);
    await HiveService.saveNote(
      CardItem(
        frontText: 'bonjour',
        backText: 'hello',
        collectionId: child.id,
        type: CardType.reversed,
        tags: const ['french'],
      ),
    );
    await HiveService.saveNote(
      CardItem(
        frontText: 'Capital {{c1::Paris}} and {{c2::Berlin}}',
        backText: 'Europe',
        collectionId: child.id,
        type: CardType.cloze,
      ),
    );
    await HiveService.saveNote(
      CardItem(
        frontText: 'Question',
        backText: 'Answer',
        collectionId: parent.id,
      ),
    );
    final image = await MediaService.storeBytes(
      bytes: Uint8List.fromList([137, 80, 78, 71]),
      fileName: 'image.png',
    );
    expect(image, isNotNull);
    final basic = HiveService.getAllCards().firstWhere(
      (card) => card.frontText == 'Question',
    );
    await HiveService.updateCard(basic.copyWith(imagePath: image));

    final result = await const AnkiExportService().build();
    expect(result.notes, 3);
    expect(result.cards, 5);
    expect(result.media, 1);
    expect(result.bytes.length, greaterThan(500));
    expect(result.warnings.join(' '), contains('Scheduling was not exported'));

    final preview = await const AnkiImportService().previewBytes(
      result.bytes,
      fileName: result.fileName,
    );
    expect(preview.noteCount, 3);
    expect(preview.generatedCardCount, 5);

    await HiveService.clearAllData();
    final imported = await const AnkiImportService().commit(preview);
    expect(imported.importedCards, 5);
    expect(HiveService.getAllCards().length, 5);
    expect(
      HiveService.getAllCollections().any((deck) => deck.name == 'French'),
      isTrue,
    );
    expect(
      HiveService.getAllCards().any(
        (card) => card.hasImage && File(card.imagePath!).existsSync(),
      ),
      isTrue,
    );
  });
}

Future<Uint8List> _buildFixturePackage() async {
  final directory = await Directory.systemTemp.createTemp('knowit_fixture_');
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
      'name': 'Reversed',
      'type': 0,
      'tmpls': [
        {'ord': 0},
        {'ord': 1},
      ],
    },
    '2': {
      'id': 2,
      'name': 'Cloze',
      'type': 1,
      'tmpls': [
        {'ord': 0},
      ],
    },
    '3': {
      'id': 3,
      'name': 'Basic',
      'type': 0,
      'tmpls': [
        {'ord': 0},
      ],
    },
  };
  final decks = {
    '1': {'id': 1, 'name': 'Default'},
    '2': {'id': 2, 'name': 'Parent'},
    '3': {'id': 3, 'name': 'Parent::Child'},
  };
  db.execute(
    'INSERT INTO col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, '
    'decks, dconf, tags) VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, ?)',
    [now, now, now, '{}', jsonEncode(models), jsonEncode(decks), '{}', '{}'],
  );
  db.execute(
    'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, '
    'flags, data) VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, \'\')',
    [100, 'g1', 1, now, ' language ', 'bonjour\x1fhello', 'bonjour', 0],
  );
  db.execute(
    'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, '
    'flags, data) VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, \'\')',
    [
      101,
      'g2',
      2,
      now,
      ' geography ',
      '{{c1::Paris}} and {{c2::Berlin}}\x1fEurope',
      'Paris and Berlin',
      0,
    ],
  );
  db.execute(
    'INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, '
    'flags, data) VALUES (?, ?, ?, ?, -1, ?, ?, ?, ?, 0, \'\')',
    [
      102,
      'g3',
      3,
      now,
      '',
      'Question <img src="pic.png">\x1fAnswer',
      'Question',
      0,
    ],
  );
  final cards = [
    (1000, 100, 2, 0),
    (1001, 100, 2, 1),
    (1002, 101, 2, 0),
    (1003, 101, 2, 1),
    (1004, 102, 3, 0),
  ];
  for (final card in cards) {
    db.execute(
      'INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, '
      'factor, reps, lapses, left, odue, odid, flags, data) '
      'VALUES (?, ?, ?, ?, ?, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, \'\')',
      [card.$1, card.$2, card.$3, card.$4, now],
    );
  }
  db.close();
  final dbBytes = await dbFile.readAsBytes();

  final archive = Archive();
  archive.addFile(ArchiveFile('collection.anki2', dbBytes.length, dbBytes));
  final mediaJson = utf8.encode(jsonEncode({'0': 'pic.png'}));
  archive.addFile(ArchiveFile('media', mediaJson.length, mediaJson));
  final media = Uint8List.fromList([137, 80, 78, 71]);
  archive.addFile(ArchiveFile('0', media.length, media));
  final encoded = ZipEncoder().encode(archive);
  try {
    directory.deleteSync(recursive: true);
  } on Object {
    // Best effort.
  }
  return Uint8List.fromList(encoded);
}
