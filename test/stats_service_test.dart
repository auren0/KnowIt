import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/services/stats_service.dart';
import 'package:knowit/utils/formatters.dart';

import 'test_helpers.dart';

void main() {
  const service = StatsService();
  final now = DateTime(2026, 11, 12, 18);

  ReviewLog log({
    required DateTime at,
    int rating = 3,
    int? previousState,
    String cardId = 'card',
    String mode = 'srs',
    int durationMs = 60000,
  }) {
    return ReviewLog(
      cardId: cardId,
      collectionId: 'deck',
      rating: rating,
      reviewedAt: at,
      previousState: previousState ?? CardLearningState.review.index,
      mode: mode,
      durationMs: durationMs,
    );
  }

  CardItem card({
    String id = 'card',
    CardLearningState state = CardLearningState.review,
    DateTime? due,
    int reps = 3,
    int lapses = 0,
    double? difficulty,
    String deckId = 'deck',
  }) {
    return CardItem(
      id: id,
      frontText: 'Question $id',
      backText: 'Answer',
      collectionId: deckId,
      state: state,
      due: due,
      reps: reps,
      lapses: lapses,
      difficulty: difficulty,
      stability: 4,
      lastReview: now.subtract(const Duration(days: 2)),
    );
  }

  test('deck metrics split new, learning, due and learned cards', () {
    final cards = [
      card(id: 'new', state: CardLearningState.newCard, reps: 0, due: null),
      card(
        id: 'learning',
        state: CardLearningState.learning,
        due: now.subtract(const Duration(minutes: 1)),
      ),
      card(id: 'due', due: now.subtract(const Duration(hours: 1))),
      card(id: 'future', due: now.add(const Duration(days: 3))),
    ];

    final metrics = service.deckMetrics(cards, now: now);

    expect(metrics.total, 4);
    expect(metrics.newCards, 1);
    expect(metrics.learning, 1);
    expect(metrics.due, 2);
    expect(metrics.learned, 3);
    expect(metrics.progress, closeTo(0.75, 0.001));
    expect(metrics.nextDue, isNotNull);
  });

  test('learning stats use real logs, streaks, retention and study time', () {
    final logs = [
      log(at: now.subtract(const Duration(hours: 1)), rating: 3),
      log(at: now.subtract(const Duration(hours: 2)), rating: 1),
      log(at: startOfDay(now).subtract(const Duration(days: 1)), rating: 3),
      log(at: startOfDay(now).subtract(const Duration(days: 2)), rating: 4),
      log(
        at: startOfDay(now).subtract(const Duration(days: 5)),
        rating: 2,
        mode: StudyMode.cram.name,
      ),
      log(
        at: now.subtract(const Duration(minutes: 10)),
        previousState: CardLearningState.newCard.index,
      ),
    ];
    final cards = [
      card(id: 'a', due: now.subtract(const Duration(minutes: 1))),
      card(id: 'b', due: now.add(const Duration(days: 2))),
      card(id: 'c', state: CardLearningState.newCard, reps: 0, due: null),
    ];

    final stats = service.learningStats(logs: logs, cards: cards, now: now);

    expect(stats.totalReviews, 6);
    expect(stats.todayReviews, 3);
    expect(stats.todayNewCards, 1);
    expect(stats.dueToday, 1);
    expect(stats.currentStreak, 3);
    expect(stats.longestStreak, 3);
    expect(stats.totalCards, 3);
    expect(stats.learnedCards, 2);
    expect(stats.totalStudyTime, const Duration(minutes: 6));
    // 4 scheduled reviews on non-new cards, 3 correct (the cram log and the
    // first exposure are excluded from retention).
    expect(stats.retentionSample, 4);
    expect(stats.retention, closeTo(0.75, 0.0001));
    expect(stats.ratingCounts[3], 3);
    expect(stats.ratingCounts[1], 1);
    expect(stats.daily.length, 30);
    expect(stats.heatmap, isNotEmpty);
    expect(stats.activeDays, 4);
  });

  test('streak continues from yesterday when today is empty', () {
    final logs = [
      log(at: startOfDay(now).subtract(const Duration(days: 1))),
      log(at: startOfDay(now).subtract(const Duration(days: 2))),
    ];
    final stats = service.learningStats(logs: logs, cards: const [], now: now);
    expect(stats.currentStreak, 2);
    expect(stats.todayReviews, 0);
  });

  test('difficult cards rank lapses and Again ratings', () {
    final cards = [
      card(id: 'easy'),
      card(id: 'forgotten', lapses: 5),
      card(id: 'sometimes', lapses: 1),
    ];
    final logs = [
      log(at: now, cardId: 'sometimes', rating: 1),
      log(at: now, cardId: 'sometimes', rating: 1),
      log(at: now, cardId: 'sometimes', rating: 1),
    ];

    final difficult = service.difficultCards(
      cards: cards,
      logs: logs,
      limit: 3,
    );

    expect(difficult.first.id, 'forgotten');
    expect(difficult.length, 2);
  });

  test('suggestions reflect due workload and empty state', () {
    final deck = makeDeck();
    final emptySuggestions = service.suggestions(
      collections: const [],
      cards: const [],
      logs: const [],
      settings: AppSettings.defaults,
    );
    expect(emptySuggestions.single.title, 'Create your first deck');

    final cards = [
      card(
        id: 'due-1',
        deckId: deck.id,
        due: now.subtract(const Duration(hours: 1)),
      ),
      card(
        id: 'due-2',
        deckId: deck.id,
        due: now.subtract(const Duration(hours: 2)),
      ),
    ];
    final suggestions = service.suggestions(
      collections: [deck],
      cards: cards,
      logs: const [],
      settings: AppSettings.defaults,
      now: now,
    );
    expect(suggestions.first.title, contains('due today'));
    expect(suggestions.first.deckId, deck.id);
  });

  test('practice logs do not lower estimated retention', () {
    final logs = [
      log(
        at: now,
        rating: 1,
        mode: StudyMode.cram.name,
        previousState: CardLearningState.review.index,
      ),
      log(at: now, rating: 3),
    ];
    final stats = service.learningStats(logs: logs, cards: const [], now: now);
    expect(stats.retentionSample, 1);
    expect(stats.retention, 1.0);
    expect(stats.totalReviews, 2);
  });
}
