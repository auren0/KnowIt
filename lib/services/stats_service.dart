import 'dart:math';

import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/utils/formatters.dart';

/// Aggregated counters for one deck.
class DeckMetrics {
  final int total;
  final int newCards;
  final int learning;
  final int due;
  final int learned;
  final DateTime? nextDue;

  const DeckMetrics({
    required this.total,
    required this.newCards,
    required this.learning,
    required this.due,
    required this.learned,
    this.nextDue,
  });

  double get progress => total == 0 ? 0 : learned / total;

  bool get hasDue => due > 0 || newCards > 0;

  static const DeckMetrics empty = DeckMetrics(
    total: 0,
    newCards: 0,
    learning: 0,
    due: 0,
    learned: 0,
  );
}

class DailyActivity {
  final DateTime date;
  final int reviews;
  final int newCards;

  const DailyActivity({
    required this.date,
    required this.reviews,
    required this.newCards,
  });
}

/// Statistics derived exclusively from persisted cards and review logs.
class LearningStats {
  final int totalReviews;
  final int totalCards;
  final int learnedCards;
  final int todayReviews;
  final int todayNewCards;
  final int dueToday;
  final int currentStreak;
  final int longestStreak;
  final double retention;
  final int retentionSample;
  final Duration totalStudyTime;
  final Map<int, int> ratingCounts;
  final List<DailyActivity> daily;
  final Map<String, int> heatmap;
  final int activeDays;

  const LearningStats({
    required this.totalReviews,
    required this.totalCards,
    required this.learnedCards,
    required this.todayReviews,
    required this.todayNewCards,
    required this.dueToday,
    required this.currentStreak,
    required this.longestStreak,
    required this.retention,
    required this.retentionSample,
    required this.totalStudyTime,
    required this.ratingCounts,
    required this.daily,
    required this.heatmap,
    required this.activeDays,
  });

  static const LearningStats empty = LearningStats(
    totalReviews: 0,
    totalCards: 0,
    learnedCards: 0,
    todayReviews: 0,
    todayNewCards: 0,
    dueToday: 0,
    currentStreak: 0,
    longestStreak: 0,
    retention: 0,
    retentionSample: 0,
    totalStudyTime: Duration.zero,
    ratingCounts: {},
    daily: [],
    heatmap: {},
    activeDays: 0,
  );
}

class StudySuggestion {
  final String title;
  final String message;
  final String actionLabel;
  final String? deckId;

  const StudySuggestion({
    required this.title,
    required this.message,
    this.actionLabel = 'Study',
    this.deckId,
  });
}

class StatsService {
  const StatsService();

  DeckMetrics deckMetrics(List<CardItem> deckCards, {DateTime? now}) {
    final current = now ?? DateTime.now();
    var newCards = 0;
    var learning = 0;
    var due = 0;
    var learned = 0;
    DateTime? nextDue;
    for (final card in deckCards) {
      if (card.isNew) {
        newCards++;
      } else {
        if (card.isLearning || card.isRelearning) learning++;
        final dueDate = card.due;
        final availableToday = card.isReview
            ? (dueDate == null || !dueDate.isAfter(endOfDay(current)))
            : card.isDue(now: current);
        if (availableToday) due++;
        if (dueDate != null && dueDate.isAfter(current)) {
          if (nextDue == null || dueDate.isBefore(nextDue)) nextDue = dueDate;
        }
      }
      if (card.reps > 0) learned++;
    }
    return DeckMetrics(
      total: deckCards.length,
      newCards: newCards,
      learning: learning,
      due: due,
      learned: learned,
      nextDue: nextDue,
    );
  }

  LearningStats learningStats({
    required List<ReviewLog> logs,
    required List<CardItem> cards,
    int heatmapDays = 119,
    int dailyDays = 30,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final today = startOfDay(current);

    final dailyCounts = <String, int>{};
    final newCounts = <String, int>{};
    final heatmap = <String, int>{};
    final ratingCounts = <int, int>{1: 0, 2: 0, 3: 0, 4: 0};
    var totalStudyMs = 0;
    var correct = 0;
    var retentionSample = 0;

    final heatmapStart = today.subtract(Duration(days: heatmapDays - 1));

    for (final log in logs) {
      final reviewedDay = startOfDay(log.reviewedAt);
      final key = dayKey(log.reviewedAt);
      dailyCounts[key] = (dailyCounts[key] ?? 0) + 1;
      if (log.previousState == CardLearningState.newCard.index) {
        newCounts[key] = (newCounts[key] ?? 0) + 1;
      }
      if (!reviewedDay.isBefore(heatmapStart)) {
        heatmap[key] = (heatmap[key] ?? 0) + 1;
      }
      ratingCounts[log.rating] = (ratingCounts[log.rating] ?? 0) + 1;
      totalStudyMs += log.durationMs;
      if (log.isScheduled &&
          log.previousState != CardLearningState.newCard.index) {
        retentionSample++;
        if (log.wasCorrect) correct++;
      }
    }

    final todayKey = dayKey(today);
    final todayReviews = dailyCounts[todayKey] ?? 0;
    final todayNew = newCounts[todayKey] ?? 0;

    var dueToday = 0;
    var learned = 0;
    for (final card in cards) {
      if (!card.isNew) {
        final due = card.due;
        if (due == null || !due.isAfter(endOfDay(current))) dueToday++;
      }
      if (card.reps > 0) learned++;
    }

    final daily = <DailyActivity>[];
    for (var offset = dailyDays - 1; offset >= 0; offset--) {
      final date = today.subtract(Duration(days: offset));
      final key = dayKey(date);
      daily.add(
        DailyActivity(
          date: date,
          reviews: dailyCounts[key] ?? 0,
          newCards: newCounts[key] ?? 0,
        ),
      );
    }

    final activeDays = dailyCounts.keys.length;
    final streak = _streaks(dailyCounts.keys.toSet(), today);

    return LearningStats(
      totalReviews: logs.length,
      totalCards: cards.length,
      learnedCards: learned,
      todayReviews: todayReviews,
      todayNewCards: todayNew,
      dueToday: dueToday,
      currentStreak: streak.$1,
      longestStreak: streak.$2,
      retention: retentionSample == 0 ? 0 : correct / retentionSample,
      retentionSample: retentionSample,
      totalStudyTime: Duration(milliseconds: totalStudyMs),
      ratingCounts: ratingCounts,
      daily: daily,
      heatmap: heatmap,
      activeDays: activeDays,
    );
  }

  /// Real review counts for a complete calendar year, keyed by day.
  /// Used by the yearly heatmap; no synthetic data is generated.
  Map<String, int> heatmapForYear(List<ReviewLog> logs, {int? year}) {
    final target = year ?? DateTime.now().year;
    final result = <String, int>{};
    for (final log in logs) {
      if (log.reviewedAt.year != target) continue;
      final key = dayKey(log.reviewedAt);
      result[key] = (result[key] ?? 0) + 1;
    }
    return result;
  }

  /// Returns (current streak, longest streak).
  (int, int) _streaks(Set<String> activeDayKeys, DateTime today) {
    if (activeDayKeys.isEmpty) return (0, 0);

    var current = 0;
    var cursor = today;
    if (!activeDayKeys.contains(dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (activeDayKeys.contains(dayKey(cursor))) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final sorted = activeDayKeys.toList()..sort();
    var longest = 1;
    var run = 1;
    for (var i = 1; i < sorted.length; i++) {
      final previous = DateTime.parse(sorted[i - 1]);
      final day = DateTime.parse(sorted[i]);
      if (day.difference(previous).inDays == 1) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 1;
      }
    }
    return (current, max(longest, current));
  }

  /// Cards that are repeatedly forgotten, ranked by lapses and Again ratings.
  List<CardItem> difficultCards({
    required List<CardItem> cards,
    required List<ReviewLog> logs,
    int limit = 5,
  }) {
    final againCounts = <String, int>{};
    for (final log in logs) {
      if (log.rating == 1) {
        againCounts[log.cardId] = (againCounts[log.cardId] ?? 0) + 1;
      }
    }
    final scored =
        cards
            .where((card) => card.lapses > 0 || (againCounts[card.id] ?? 0) > 0)
            .toList()
          ..sort((a, b) {
            double score(CardItem card) =>
                card.lapses * 2.0 +
                (againCounts[card.id] ?? 0) +
                (card.difficulty ?? 0) / 10;
            return score(b).compareTo(score(a));
          });
    return scored.take(limit).toList();
  }

  List<StudySuggestion> suggestions({
    required List<Collection> collections,
    required List<CardItem> cards,
    required List<ReviewLog> logs,
    required AppSettings settings,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final stats = learningStats(logs: logs, cards: cards, now: current);
    final l10n = AppLocalizations.current;
    final result = <StudySuggestion>[];

    if (collections.isEmpty) {
      return [
        StudySuggestion(
          title: l10n.suggestionCreateDeck,
          message: l10n.suggestionCreateDeckMessage,
          actionLabel: l10n.suggestionCreateDeckAction,
        ),
      ];
    }
    if (cards.isEmpty) {
      return [
        StudySuggestion(
          title: l10n.suggestionAddCard,
          message: l10n.suggestionAddCardMessage,
          actionLabel: l10n.suggestionAddCardAction,
        ),
      ];
    }

    if (stats.dueToday > 0) {
      final dueByDeck = <String, int>{};
      for (final card in cards) {
        if (!card.isNew && card.isDue(now: current)) {
          dueByDeck[card.collectionId] =
              (dueByDeck[card.collectionId] ?? 0) + 1;
        }
      }
      final topDeck = dueByDeck.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final deck = topDeck.isEmpty
          ? null
          : collections.cast<Collection?>().firstWhere(
              (item) => item?.id == topDeck.first.key,
              orElse: () => null,
            );
      result.add(
        StudySuggestion(
          title: l10n.dueTodaySuggestionTitle(stats.dueToday),
          message: deck == null
              ? l10n.dueTodaySuggestionMessage
              : l10n.dueTodaySuggestionDeck(deck.name, topDeck.first.value),
          deckId: deck?.id,
        ),
      );
    }

    final difficult = difficultCards(cards: cards, logs: logs, limit: 3);
    if (difficult.length >= 2) {
      final deck = collections.cast<Collection?>().firstWhere(
        (item) => item?.id == difficult.first.collectionId,
        orElse: () => null,
      );
      result.add(
        StudySuggestion(
          title: l10n.slippingSuggestionTitle(difficult.length),
          message: l10n.slippingSuggestionMessage(deck?.name ?? ''),
          actionLabel: l10n.practiceSuggestionAction,
          deckId: deck?.id,
        ),
      );
    }

    if (stats.retentionSample >= 20 &&
        stats.retention < settings.desiredRetention - 0.05) {
      result.add(
        StudySuggestion(
          title: l10n.retentionSuggestionTitle((stats.retention * 100).round()),
          message: l10n.retentionSuggestionMessage(
            (settings.desiredRetention * 100).round(),
          ),
          actionLabel: l10n.reviewSuggestionAction,
        ),
      );
    }

    if (result.isEmpty && stats.currentStreak > 0 && stats.todayReviews == 0) {
      result.add(
        StudySuggestion(
          title: l10n.streakSuggestionTitle(stats.currentStreak),
          message: l10n.streakSuggestionMessage,
        ),
      );
    }

    if (result.isEmpty) {
      final remaining = settings.dailyGoal - stats.todayReviews;
      result.add(
        remaining > 0
            ? StudySuggestion(
                title: l10n.goalSuggestionTitle(
                  stats.todayReviews,
                  settings.dailyGoal,
                ),
                message: l10n.goalSuggestionMessage(remaining),
              )
            : StudySuggestion(
                title: l10n.goalReachedTitle,
                message: l10n.goalReachedMessage,
              ),
      );
    }

    return result.take(3).toList();
  }
}
