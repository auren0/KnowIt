import 'dart:math';

import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/utils/formatters.dart';

class StudyQueue {
  final List<CardItem> cards;
  final bool hitNewLimit;
  final bool hitReviewLimit;

  const StudyQueue(
    this.cards, {
    this.hitNewLimit = false,
    this.hitReviewLimit = false,
  });

  bool get isEmpty => cards.isEmpty;
  int get length => cards.length;
}

/// Builds study queues for every mode.
///
/// Only [StudyMode.srs] applies daily new/review limits. Practice modes never
/// write scheduling data; that decision is enforced by the study screen via
/// [StudyMode.changesSchedule] and by [SchedulerService.practiceLog].
class StudyQueueService {
  const StudyQueueService();

  StudyQueue build({
    required List<CardItem> cards,
    required StudyMode mode,
    required AppSettings settings,
    List<ReviewLog> logs = const [],
    DateTime? now,
    int? maxCards,
    Random? random,
  }) {
    final current = now ?? DateTime.now();
    List<CardItem> selected;

    switch (mode) {
      case StudyMode.srs:
        return _buildSrs(
          cards: cards,
          settings: settings,
          logs: logs,
          now: current,
          maxCards: maxCards,
        );
      case StudyMode.quick:
        selected = _quickQueue(cards, current);
      case StudyMode.cram:
        selected = List<CardItem>.from(cards)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case StudyMode.random:
        selected = List<CardItem>.from(cards)..shuffle(random ?? Random());
      case StudyMode.difficult:
        selected = _difficultQueue(cards, logs);
    }

    if (maxCards != null && selected.length > maxCards) {
      selected = selected.sublist(0, maxCards);
    }
    return StudyQueue(selected);
  }

  StudyQueue _buildSrs({
    required List<CardItem> cards,
    required AppSettings settings,
    required List<ReviewLog> logs,
    required DateTime now,
    int? maxCards,
  }) {
    final due = cards.where((card) => _isDueForSession(card, now)).toList();
    final learning =
        due.where((card) => card.isLearning || card.isRelearning).toList()
          ..sort(_byDue);
    final reviewDue = due.where((card) => card.isReview).toList()..sort(_byDue);
    final newCards = cards.where((card) => card.isNew).toList()
      ..sort((a, b) {
        final created = a.createdAt.compareTo(b.createdAt);
        return created != 0 ? created : a.id.compareTo(b.id);
      });

    final todayLogs = logs.where(
      (log) => log.isScheduled && isSameDay(log.reviewedAt, now),
    );
    final newStudiedToday = todayLogs
        .where((log) => log.previousState == CardLearningState.newCard.index)
        .length;
    final reviewsDoneToday = todayLogs
        .where((log) => log.previousState != CardLearningState.newCard.index)
        .length;

    final newLimit = max(0, settings.newCardsPerDay - newStudiedToday);
    final reviewLimit = max(0, settings.reviewsPerDay - reviewsDoneToday);
    final limitedReviews = reviewDue.take(reviewLimit).toList();
    final limitedNew = newCards.take(newLimit).toList();

    var queue = <CardItem>[...learning, ...limitedReviews, ...limitedNew];
    if (maxCards != null && queue.length > maxCards) {
      queue = queue.sublist(0, maxCards);
    }
    return StudyQueue(
      queue,
      hitNewLimit: newCards.length > limitedNew.length,
      hitReviewLimit: reviewDue.length > limitedReviews.length,
    );
  }

  List<CardItem> _quickQueue(List<CardItem> cards, DateTime now) {
    final due = cards.where((card) => _isDueForSession(card, now)).toList()
      ..sort(_byDue);
    if (due.isNotEmpty) return due;

    final reviewed = cards.where((card) => card.lastReview != null).toList()
      ..sort((a, b) => a.lastReview!.compareTo(b.lastReview!));
    if (reviewed.isNotEmpty) return reviewed.take(20).toList();

    return cards.where((card) => card.isNew).take(20).toList();
  }

  List<CardItem> _difficultQueue(List<CardItem> cards, List<ReviewLog> logs) {
    final againCounts = <String, int>{};
    for (final log in logs) {
      if (log.rating == 1) {
        againCounts[log.cardId] = (againCounts[log.cardId] ?? 0) + 1;
      }
    }

    double score(CardItem card) =>
        card.lapses * 3.0 +
        (againCounts[card.id] ?? 0) * 1.5 +
        (card.difficulty ?? 0);

    final scored = cards.where((card) => score(card) > 0).toList()
      ..sort((a, b) => score(b).compareTo(score(a)));

    if (scored.isNotEmpty) return scored;

    // No failure history yet: fall back to cards with the highest difficulty
    // (or the oldest reviewed cards) so the mode is still useful.
    final reviewed = cards.where((card) => !card.isNew).toList()
      ..sort((a, b) {
        final difficulty = (b.difficulty ?? 0).compareTo(a.difficulty ?? 0);
        if (difficulty != 0) return difficulty;
        final aDate = a.lastReview ?? a.createdAt;
        final bDate = b.lastReview ?? b.createdAt;
        return aDate.compareTo(bDate);
      });
    return reviewed.take(20).toList();
  }

  static int _byDue(CardItem a, CardItem b) {
    final aDue = a.due ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDue = b.due ?? DateTime.fromMillisecondsSinceEpoch(0);
    final due = aDue.compareTo(bDue);
    if (due != 0) return due;
    return a.queuePriority.compareTo(b.queuePriority);
  }

  /// Review-state cards become available at the start of their due day (local
  /// day boundary); sub-day learning steps stay minute-precise.
  static bool _isDueForSession(CardItem card, DateTime now) {
    if (card.isNew) return false;
    final due = card.due;
    if (due == null) return true;
    if (card.isReview) return !due.isAfter(endOfDay(now));
    return !due.isAfter(now);
  }
}
