import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/services/hive_service.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(initTestHive);
  tearDown(initTestHive);
  tearDownAll(closeTestHive);

  test('deck and card CRUD keeps ids and counts consistent', () async {
    final deck = makeDeck(name: 'Biology');
    await HiveService.createCollection(deck);

    final card = makeCard(collectionId: deck.id, front: 'Cell');
    await HiveService.addCard(card);

    expect(HiveService.getAllCollections().length, 1);
    expect(HiveService.getCardsByCollection(deck.id).length, 1);
    expect(HiveService.getCollection(deck.id)!.cardCount, 1);

    await HiveService.updateCard(card.copyWith(frontText: 'Cell theory'));
    expect(HiveService.getCard(card.id)!.frontText, 'Cell theory');

    final deleted = await HiveService.deleteCard(card.id);
    expect(deleted!.id, card.id);
    expect(HiveService.getCardsByCollection(deck.id), isEmpty);
    expect(HiveService.getCollection(deck.id)!.cardCount, 0);
  });

  test('cards can be moved between decks', () async {
    final source = makeDeck(name: 'Source');
    final target = makeDeck(name: 'Target');
    await HiveService.createCollection(source);
    await HiveService.createCollection(target);
    final card = makeCard(collectionId: source.id);
    await HiveService.addCard(card);

    await HiveService.moveCards([card.id], target.id);

    expect(HiveService.getCardsByCollection(source.id), isEmpty);
    expect(HiveService.getCardsByCollection(target.id).single.id, card.id);
    expect(HiveService.getCollection(source.id)!.cardCount, 0);
    expect(HiveService.getCollection(target.id)!.cardCount, 1);
  });

  test('deleted cards can be restored for undo', () async {
    final deck = makeDeck();
    await HiveService.createCollection(deck);
    final card = makeCard(collectionId: deck.id);
    await HiveService.addCard(card);

    final removed = await HiveService.deleteCards([card.id]);
    expect(removed.length, 1);

    await HiveService.restoreCards(removed);
    expect(HiveService.getCard(card.id), isNotNull);
    expect(HiveService.getCollection(deck.id)!.cardCount, 1);
  });

  test('cascading deck delete removes subdecks and can be undone', () async {
    final parent = makeDeck(name: 'Parent');
    await HiveService.createCollection(parent);
    final child = makeDeck(name: 'Child', parentId: parent.id);
    await HiveService.createCollection(child);
    final parentCard = makeCard(collectionId: parent.id);
    final childCard = makeCard(collectionId: child.id);
    await HiveService.addCard(parentCard);
    await HiveService.addCard(childCard);
    await HiveService.addLog(
      ReviewLog(
        cardId: childCard.id,
        collectionId: child.id,
        rating: 3,
        reviewedAt: DateTime.now(),
      ),
    );

    final snapshot = await HiveService.deleteCollectionCascade(parent.id);

    expect(snapshot, isNotNull);
    expect(snapshot!.cards.length, 2);
    expect(snapshot.logs.length, 1);
    expect(HiveService.getAllCollections(), isEmpty);
    expect(HiveService.getAllCards(), isEmpty);
    expect(HiveService.getAllLogs(), isEmpty);

    await HiveService.restoreDeckSnapshot(snapshot);
    expect(HiveService.getAllCollections().length, 2);
    expect(HiveService.getAllCards().length, 2);
    expect(HiveService.getAllLogs().length, 1);
    expect(HiveService.getCollection(parent.id)!.cardCount, 2);
  });

  test('deep duplicate creates independent decks and cards', () async {
    final parent = makeDeck(name: 'Parent');
    await HiveService.createCollection(parent);
    final child = makeDeck(name: 'Child', parentId: parent.id);
    await HiveService.createCollection(child);
    await HiveService.addCard(makeCard(collectionId: parent.id));
    await HiveService.addCard(makeCard(collectionId: child.id));

    final copies = await HiveService.duplicateCollection(parent.id);
    final copiedParent = copies.first;

    expect(copies.length, 2);
    expect(copiedParent.name, 'Parent (copy)');
    expect(copiedParent.id, isNot(parent.id));
    final copiesInNewTree = HiveService.getCardsByCollection(copiedParent.id);
    expect(copiesInNewTree.length, 2);
    final originalTree = HiveService.getCardsByCollection(parent.id);
    expect(originalTree.length, 2);
    expect(
      copiesInNewTree
          .map((card) => card.id)
          .toSet()
          .intersection(originalTree.map((card) => card.id).toSet()),
      isEmpty,
    );
  });

  test('repair normalizes legacy keys and orphaned cards', () async {
    final deck = makeDeck(name: 'Legacy');
    await HiveService.createCollection(deck);
    final card = makeCard(collectionId: deck.id);
    await HiveService.addCard(card);
    final orphan = makeCard(collectionId: 'missing-deck');

    final rawCards = Hive.box<CardItem>('cards');
    await rawCards.delete(card.id);
    await rawCards.put('legacy-key', card);
    await rawCards.put('orphan-key', orphan);

    await HiveService.repairDatabase();

    expect(HiveService.getCard(card.id), isNotNull);
    expect(HiveService.getCard(orphan.id), isNotNull);
    final repairedOrphan = HiveService.getCard(orphan.id)!;
    final recoveredDeck = HiveService.getCollection(
      repairedOrphan.collectionId,
    );
    expect(recoveredDeck, isNotNull);
    expect(recoveredDeck!.name, 'Recovered cards');
    expect(
      HiveService.getAllCollections().any(
        (item) => item.name == 'Recovered cards',
      ),
      isTrue,
    );
  });

  test('review logs are stored, queryable and undoable', () async {
    final deck = makeDeck();
    await HiveService.createCollection(deck);
    final card = makeCard(collectionId: deck.id);
    await HiveService.addCard(card);
    final original = card;
    final log = ReviewLog(
      cardId: card.id,
      collectionId: deck.id,
      rating: 3,
      reviewedAt: DateTime.now(),
      previousState: CardLearningState.newCard.index,
    );
    await HiveService.addLog(log);
    await HiveService.updateCard(
      card.copyWith(state: CardLearningState.learning, reps: 1),
    );

    expect(HiveService.getLogsForCard(card.id).length, 1);

    await HiveService.undoReview(original, log.id);

    expect(HiveService.getCard(card.id)!.state, CardLearningState.newCard);
    expect(HiveService.getLogsForCard(card.id), isEmpty);
  });

  test('collections are returned in manual order', () async {
    final first = makeDeck(name: 'First').copyWith(sortOrder: 1);
    final second = makeDeck(name: 'Second').copyWith(sortOrder: 2);
    await HiveService.createCollection(second);
    await HiveService.createCollection(first);

    final all = HiveService.getAllCollections();
    expect(all.first.id, first.id);
    expect(all.last.id, second.id);
  });

  test('collection serialization round-trips', () {
    final deck = makeDeck(
      name: 'Roundtrip',
      parentId: 'parent',
    ).copyWith(description: 'Notes', sortOrder: 4);
    final restored = Collection.fromJson(deck.toJson());

    expect(restored.id, deck.id);
    expect(restored.parentId, 'parent');
    expect(restored.description, 'Notes');
    expect(restored.colorValue, deck.colorValue);
    expect(restored.sortOrder, 4);
  });
}
