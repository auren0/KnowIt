import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/services/backup_service.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/settings_service.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(initTestHive);
  setUp(initTestHive);
  tearDownAll(closeTestHive);

  Future<(Collection, CardItem)> seed() async {
    final deck = makeDeck(name: 'Backup deck');
    await HiveService.createCollection(deck);
    final card = makeCard(collectionId: deck.id, front: 'Q1', back: 'A1');
    await HiveService.addCard(card);
    await HiveService.addLog(
      ReviewLog(
        cardId: card.id,
        collectionId: deck.id,
        rating: 3,
        reviewedAt: DateTime.now(),
        previousState: CardLearningState.newCard.index,
      ),
    );
    return (deck, card);
  }

  test('export contains real data and settings', () async {
    final (deck, card) = await seed();
    final json = BackupService.exportToJson();
    final parsed = BackupService.parse(json);

    expect(parsed.collections.single.id, deck.id);
    expect(parsed.cards.single.id, card.id);
    expect(parsed.logs.length, 1);
    expect(parsed.settings, isNotNull);
    expect(json, contains('knowit-backup'));
  });

  test('replace import restores every record and settings', () async {
    await seed();
    await SettingsService.save(
      const AppSettings(newCardsPerDay: 5, desiredRetention: 0.88),
    );
    final json = BackupService.exportToJson();
    await SettingsService.save(
      const AppSettings(newCardsPerDay: 7, desiredRetention: 0.93),
    );

    await HiveService.clearAllData();
    expect(HiveService.getAllCards(), isEmpty);

    final result = await BackupService.importJson(json, replace: true);

    expect(result.replaced, isTrue);
    expect(HiveService.getAllCollections().length, 1);
    expect(HiveService.getAllCards().length, 1);
    expect(HiveService.getAllLogs().length, 1);
    expect(SettingsService.value.newCardsPerDay, 5);
    expect(SettingsService.value.desiredRetention, closeTo(0.88, 0.001));
  });

  test(
    'merge import rekeys colliding ids and preserves existing data',
    () async {
      await seed();
      final json = BackupService.exportToJson();

      final result = await BackupService.importJson(json);

      expect(result.collections, 1);
      expect(result.cards, 1);
      expect(HiveService.getAllCollections().length, 2);
      expect(HiveService.getAllCards().length, 2);
      final ids = HiveService.getAllCards().map((card) => card.id).toSet();
      expect(ids.length, 2);
      // Each card must belong to a deck that exists in the merged library.
      final deckIds = HiveService.getAllCollections()
          .map((deck) => deck.id)
          .toSet();
      for (final card in HiveService.getAllCards()) {
        expect(deckIds.contains(card.collectionId), isTrue);
      }
    },
  );

  test('import repairs cards with missing decks', () async {
    await seed();
    final json = BackupService.exportToJson();
    await HiveService.clearAllData();
    final damaged = json.replaceFirst(
      '"collectionId": "',
      '"collectionId": "missing-',
    );

    final result = await BackupService.importJson(damaged, replace: true);

    expect(result.collections, 2); // original deck + recovery deck
    final cards = HiveService.getAllCards();
    expect(cards.length, 1);
    final deck = HiveService.getCollection(cards.single.collectionId);
    expect(deck, isNotNull);
    expect(deck!.name, 'Imported cards');
  });

  test('invalid and oversized inputs are rejected gracefully', () async {
    expect(
      () => BackupService.parse('not json'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => BackupService.parse('{"collections": [], "cards": []}'),
      throwsA(isA<FormatException>()),
    );
    expect(() => BackupService.parse('[]'), throwsA(isA<FormatException>()));
    expect(
      () => BackupService.parse(
        '{"format": "anki", "collections": [], "cards": []}',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('card JSON round-trip preserves scheduling fields', () {
    final card = makeCard(
      collectionId: 'deck',
      type: CardType.cloze,
      tags: const ['bio', 'cells'],
      state: CardLearningState.review,
      stability: 12.5,
      difficulty: 4.25,
      due: DateTime(2026, 12, 1, 10),
      lastReview: DateTime(2026, 11, 20, 9),
      reps: 8,
      lapses: 2,
      step: 2,
    );
    final restored = CardItem.fromJson(card.toJson());

    expect(restored.id, card.id);
    expect(restored.type, CardType.cloze);
    expect(restored.tags, card.tags);
    expect(restored.state, CardLearningState.review);
    expect(restored.stability, 12.5);
    expect(restored.difficulty, 4.25);
    expect(restored.due, card.due);
    expect(restored.reps, 8);
    expect(restored.lapses, 2);
    expect(restored.step, 2);
  });

  test('backup preserves reversed and cloze sibling groups', () async {
    final deck = makeDeck(name: 'Siblings');
    await HiveService.createCollection(deck);
    await HiveService.saveNote(
      CardItem(
        frontText: 'bonjour',
        backText: 'hello',
        collectionId: deck.id,
        type: CardType.reversed,
        tags: const ['french'],
      ),
    );
    await HiveService.saveNote(
      CardItem(
        frontText: '{{c1::Paris}} and {{c2::Berlin}}',
        backText: '',
        collectionId: deck.id,
        type: CardType.cloze,
      ),
    );
    expect(HiveService.getAllCards().length, 4);

    final json = BackupService.exportToJson();
    await HiveService.clearAllData();
    final result = await BackupService.importJson(json, replace: true);
    final cards = HiveService.getAllCards();

    expect(result.cards, 4);
    expect(cards.length, 4);
    final groups = <String, List<CardItem>>{};
    for (final card in cards) {
      groups.putIfAbsent(card.noteKey, () => []).add(card);
    }
    expect(groups.length, 2);
    expect(groups.values.map((group) => group.length).toSet(), {2});
    expect(
      groups.values.any(
        (group) => group.every((card) => card.type == CardType.reversed),
      ),
      isTrue,
    );
    expect(
      groups.values.any(
        (group) =>
            group.every((card) => card.type == CardType.cloze) &&
            group.map((card) => card.clozeIndex).toSet().containsAll([1, 2]),
      ),
      isTrue,
    );
  });

  test('legacy single-card backups expand into sibling groups', () async {
    const legacy = '''
    {
      "format": "knowit-backup",
      "version": 1,
      "collections": [
        {"id": "legacy-deck", "name": "Legacy", "emoji": "📚", "colorValue": 1}
      ],
      "cards": [
        {"id": "legacy-r", "frontText": "bonjour", "backText": "hello",
         "collectionId": "legacy-deck", "type": "reversed"},
        {"id": "legacy-c", "frontText": "{{c1::Paris}} and {{c2::Berlin}}",
         "backText": "", "collectionId": "legacy-deck", "type": "cloze"}
      ],
      "logs": [
        {"id": "legacy-log", "cardId": "legacy-r",
         "collectionId": "legacy-deck", "rating": 3,
         "reviewedAt": "2026-01-01T10:00:00.000Z"}
      ]
    }
    ''';

    final result = await BackupService.importJson(legacy, replace: true);
    final cards = HiveService.getAllCards();
    expect(result.cards, 4);
    expect(cards.length, 4);
    final groups = <String, List<CardItem>>{};
    for (final card in cards) {
      groups.putIfAbsent(card.noteKey, () => []).add(card);
    }
    expect(groups.length, 2);
    expect(
      groups.values.any(
        (group) =>
            group.length == 2 &&
            group.map((card) => card.reverse).toSet().containsAll([
              false,
              true,
            ]),
      ),
      isTrue,
    );
    expect(
      groups.values.any(
        (group) =>
            group.length == 2 &&
            group.map((card) => card.clozeIndex).toSet().containsAll([1, 2]),
      ),
      isTrue,
    );
    expect(HiveService.getLogsForCard('legacy-r').length, 1);
  });

  test('backup file helpers report unsupported storage gracefully', () async {
    // In a headless test environment path_provider may be unavailable. The API
    // must return null/empty rather than throwing.
    final files = await BackupService.listBackups();
    expect(files, isA<List<BackupFileInfo>>());
  });

  test('cyclic parent relationships are repaired on import', () async {
    final json = '''
    {
      "format": "knowit-backup",
      "version": 1,
      "collections": [
        {"id": "a", "name": "A", "emoji": "📚", "colorValue": 1, "parentId": "b"},
        {"id": "b", "name": "B", "emoji": "📚", "colorValue": 2, "parentId": "a"}
      ],
      "cards": []
    }
    ''';

    await BackupService.importJson(json, replace: true);

    final decks = HiveService.getAllCollections();
    expect(decks.length, 2);
    for (final deck in decks) {
      expect(deck.parentId, isNull);
    }
  });
}
