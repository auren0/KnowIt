import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/sync/sync_service.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(initTestHive);
  setUp(initTestHive);
  tearDownAll(closeTestHive);

  test('local payload includes records and deletion tombstones', () async {
    final deck = makeDeck(name: 'Sync');
    await HiveService.createCollection(deck);
    final card = makeCard(collectionId: deck.id);
    await HiveService.addCard(card);
    await HiveService.deleteCard(card.id);

    const service = SyncService();
    final payload = service.exportPayload();
    final json = payload.toJson();
    final restored = SyncPayload.fromJson(json);

    expect(restored.collections.length, 1);
    expect(restored.cards, isEmpty);
    expect(restored.tombstones.length, 1);
    expect(restored.tombstones.single.entityId, card.id);
  });

  test('newer remote records update local records', () async {
    final deck = makeDeck(name: 'Sync');
    await HiveService.createCollection(deck);
    final card = makeCard(collectionId: deck.id, front: 'Local', back: 'A');
    await HiveService.addCard(card);
    final now = DateTime.now();
    final remote = card.copyWith(
      frontText: 'Remote',
      updatedAt: now.add(const Duration(hours: 1)),
      reps: 1,
    );

    const service = SyncService();
    final plan = service.planMerge(
      SyncPayload(cards: [remote], collections: [deck]),
    );
    expect(plan.cardsToSave.length, 1);
    expect(plan.conflicts, isEmpty);

    final result = await service.applyPlan(plan);
    expect(result.cardsSaved, 1);
    expect(HiveService.getCard(card.id)!.frontText, 'Remote');
  });

  test(
    'older remote records do not overwrite newer local study state',
    () async {
      final deck = makeDeck(name: 'Sync');
      await HiveService.createCollection(deck);
      final now = DateTime.now();
      final card = makeCard(collectionId: deck.id, front: 'Local').copyWith(
        updatedAt: now,
        reps: 5,
        state: CardLearningState.review,
        stability: 10.0,
      );
      await HiveService.addCard(card);
      final remote = card.copyWith(
        frontText: 'Remote',
        updatedAt: now.subtract(const Duration(hours: 2)),
        reps: 4,
      );

      const service = SyncService();
      await service.merge(SyncPayload(cards: [remote]));

      expect(HiveService.getCard(card.id)!.frontText, 'Local');
      expect(HiveService.getCard(card.id)!.reps, 5);
    },
  );

  test('newer remote card with fewer reps is treated as a conflict', () async {
    final deck = makeDeck(name: 'Sync');
    await HiveService.createCollection(deck);
    final now = DateTime.now();
    final card = makeCard(
      collectionId: deck.id,
      front: 'Local',
    ).copyWith(updatedAt: now, reps: 6, state: CardLearningState.review);
    await HiveService.addCard(card);
    final remote = card.copyWith(
      frontText: 'Remote',
      updatedAt: now.add(const Duration(hours: 1)),
      reps: 2,
    );

    const service = SyncService();
    final plan = service.planMerge(SyncPayload(cards: [remote]));
    expect(plan.cardsToSave, isEmpty);
    expect(plan.conflicts, isNotEmpty);

    await service.applyPlan(plan);
    expect(HiveService.getCard(card.id)!.reps, 6);
    expect(HiveService.getCard(card.id)!.frontText, 'Local');
  });

  test('review logs are unioned and never removed by sync', () async {
    final deck = makeDeck(name: 'Sync');
    await HiveService.createCollection(deck);
    final card = makeCard(collectionId: deck.id);
    await HiveService.addCard(card);
    final localLog = ReviewLog(
      cardId: card.id,
      collectionId: deck.id,
      rating: 3,
      reviewedAt: DateTime.now(),
    );
    await HiveService.addLog(localLog);
    final remoteLog = ReviewLog(
      cardId: card.id,
      collectionId: deck.id,
      rating: 4,
      reviewedAt: DateTime.now().subtract(const Duration(days: 1)),
    );

    const service = SyncService();
    final result = await service.merge(
      SyncPayload(logs: [localLog, remoteLog]),
    );

    expect(result.logsAdded, 1);
    expect(HiveService.getAllLogs().length, 2);
  });

  test('remote deletion is blocked by newer local study progress', () async {
    final deck = makeDeck(name: 'Sync');
    await HiveService.createCollection(deck);
    final card = makeCard(collectionId: deck.id);
    await HiveService.addCard(card);
    final now = DateTime.now();
    final studied = card.copyWith(
      updatedAt: now.add(const Duration(hours: 1)),
      reps: 3,
    );
    await HiveService.updateCard(studied);
    await HiveService.deleteCard(card.id);
    // Simulate a remote tombstone older than the local study update.
    await HiveService.restoreCards([studied]);
    final remoteTombstone = SyncTombstone(
      entityType: SyncEntityType.card,
      entityId: card.id,
      deletedAt: now,
    );

    const service = SyncService();
    final plan = service.planMerge(SyncPayload(tombstones: [remoteTombstone]));

    expect(plan.cardIdsToDelete, isEmpty);
    expect(plan.conflicts, isNotEmpty);
    expect(HiveService.getCard(card.id), isNotNull);
  });

  test('remote deletion removes an unchanged local card', () async {
    final deck = makeDeck(name: 'Sync');
    await HiveService.createCollection(deck);
    final card = makeCard(collectionId: deck.id);
    await HiveService.addCard(card);
    final tombstone = SyncTombstone(
      entityType: SyncEntityType.card,
      entityId: card.id,
      deletedAt: DateTime.now().add(const Duration(minutes: 1)),
    );

    const service = SyncService();
    await service.merge(SyncPayload(tombstones: [tombstone]));

    expect(HiveService.getCard(card.id), isNull);
  });

  test('payload JSON round-trips and rejects unrelated formats', () {
    final deck = makeDeck(name: 'Sync');
    final card = makeCard(collectionId: deck.id, reverse: true);
    final payload = SyncPayload(
      collections: [deck],
      cards: [card],
      logs: [
        ReviewLog(
          cardId: card.id,
          collectionId: deck.id,
          rating: 3,
          reviewedAt: DateTime.now(),
        ),
      ],
      tombstones: [
        SyncTombstone(
          entityType: SyncEntityType.collection,
          entityId: 'gone',
          deletedAt: DateTime.now(),
        ),
      ],
    );
    final restored = SyncPayload.fromJson(payload.toJson());
    expect(restored.collections.single.id, deck.id);
    expect(restored.cards.single.id, card.id);
    expect(restored.logs.length, 1);
    expect(restored.tombstones.length, 1);

    expect(
      () => SyncPayload.fromJson({'format': 'unknown'}),
      throwsA(isA<FormatException>()),
    );
  });
}
