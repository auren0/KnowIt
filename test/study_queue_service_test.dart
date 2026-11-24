import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/services/study_queue_service.dart';

void main() {
  const service = StudyQueueService();
  final now = DateTime(2026, 11, 12, 10);
  const settings = AppSettings(newCardsPerDay: 2, reviewsPerDay: 1);

  CardItem card(
    String id, {
    CardLearningState state = CardLearningState.newCard,
    DateTime? due,
    int lapses = 0,
    double? difficulty,
    String front = 'Q',
  }) {
    return CardItem(
      id: id,
      frontText: front,
      backText: 'A',
      collectionId: 'deck',
      state: state,
      due: due,
      lapses: lapses,
      difficulty: difficulty,
      reps: state == CardLearningState.newCard ? 0 : 3,
      lastReview: state == CardLearningState.newCard
          ? null
          : now.subtract(const Duration(days: 1)),
    );
  }

  List<ReviewLog> todaysLogs(CardItem card, {int previousState = 0}) => [
    ReviewLog(
      cardId: card.id,
      collectionId: card.collectionId,
      rating: 3,
      reviewedAt: now.subtract(const Duration(minutes: 5)),
      previousState: previousState,
      mode: StudyMode.srs.name,
    ),
  ];

  test('SRS queue contains due cards and respects daily limits', () {
    final learning = card(
      'learning',
      state: CardLearningState.learning,
      due: now.subtract(const Duration(minutes: 1)),
    );
    final review1 = card(
      'review-1',
      state: CardLearningState.review,
      due: now.subtract(const Duration(hours: 1)),
    );
    final review2 = card(
      'review-2',
      state: CardLearningState.review,
      due: now.subtract(const Duration(hours: 2)),
    );
    final future = card(
      'future',
      state: CardLearningState.review,
      due: now.add(const Duration(days: 2)),
    );
    final new1 = card('new-1');
    final new2 = card('new-2');
    final new3 = card('new-3');

    final queue = service.build(
      cards: [learning, review1, review2, future, new1, new2, new3],
      mode: StudyMode.srs,
      settings: settings,
      now: now,
    );

    expect(queue.cards.map((item) => item.id).toSet(), {
      'learning',
      'review-2',
      'new-1',
      'new-2',
    });
    expect(queue.cards.any((item) => item.id == 'future'), isFalse);
    expect(queue.hitNewLimit, isTrue);
    expect(queue.hitReviewLimit, isTrue);
    expect(queue.cards.first.id, 'learning');
  });

  test('limits account for study already logged today', () {
    final studied = CardItem(
      id: 'studied',
      frontText: 'Already studied',
      backText: 'A',
      collectionId: 'deck',
      state: CardLearningState.learning,
      due: now.add(const Duration(minutes: 5)),
      reps: 1,
      lastReview: now.subtract(const Duration(minutes: 5)),
    );
    final new2 = card('new-2');
    final logs = todaysLogs(studied);

    final queue = service.build(
      cards: [studied, new2],
      mode: StudyMode.srs,
      settings: const AppSettings(newCardsPerDay: 2),
      logs: logs,
      now: now,
    );

    expect(queue.cards.length, 1);
    expect(queue.cards.single.id, 'new-2');
  });

  test('practice modes ignore new and review limits', () {
    final cards = [for (var index = 0; index < 8; index++) card('new-$index')];
    final cram = service.build(
      cards: cards,
      mode: StudyMode.cram,
      settings: const AppSettings(newCardsPerDay: 0, reviewsPerDay: 0),
      now: now,
    );
    expect(cram.cards.length, 8);
    expect(cram.hitNewLimit, isFalse);
  });

  test('quick mode falls back to reviewed cards when nothing is due', () {
    final reviewed = card(
      'reviewed',
      state: CardLearningState.review,
      due: now.add(const Duration(days: 3)),
    );
    final future = card(
      'future',
      state: CardLearningState.review,
      due: now.add(const Duration(days: 5)),
    );

    final queue = service.build(
      cards: [reviewed, future],
      mode: StudyMode.quick,
      settings: settings,
      now: now,
    );

    expect(queue.cards.length, 2);
  });

  test('random mode preserves every card', () {
    final cards = [for (var index = 0; index < 6; index++) card('card-$index')];
    final queue = service.build(
      cards: cards,
      mode: StudyMode.random,
      settings: settings,
      now: now,
      random: Random(7),
    );
    expect(queue.cards.length, cards.length);
    expect(
      queue.cards.map((item) => item.id).toSet(),
      cards.map((item) => item.id).toSet(),
    );
  });

  test('difficult mode puts forgotten cards first', () {
    final easy = card('easy', state: CardLearningState.review, due: now);
    final hard = card(
      'hard',
      state: CardLearningState.review,
      due: now,
      lapses: 6,
      difficulty: 8,
    );
    final queue = service.build(
      cards: [easy, hard],
      mode: StudyMode.difficult,
      settings: settings,
      now: now,
    );
    expect(queue.cards.first.id, 'hard');
  });

  test('maxCards caps the queue', () {
    final cards = [for (var index = 0; index < 5; index++) card('c$index')];
    final queue = service.build(
      cards: cards,
      mode: StudyMode.cram,
      settings: settings,
      now: now,
      maxCards: 2,
    );
    expect(queue.cards.length, 2);
  });
}
