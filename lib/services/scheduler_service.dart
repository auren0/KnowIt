import 'package:fsrs/fsrs.dart' hide ReviewLog;
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/models/study_mode.dart';

/// Result of applying an FSRS rating.
class ScheduledReview {
  final CardItem card;
  final ReviewLog log;
  final Duration interval;

  const ScheduledReview({
    required this.card,
    required this.log,
    required this.interval,
  });
}

/// Thin, testable adapter around the official Dart FSRS implementation.
///
/// The scheduler is completely independent from the UI and from persistence.
/// All dates are passed to FSRS in UTC; the returned card uses local time so the
/// rest of the app can reason about local day boundaries.
class SchedulerService {
  final bool enableFuzzing;

  const SchedulerService({this.enableFuzzing = false});

  Scheduler createScheduler(AppSettings settings) {
    return Scheduler(
      desiredRetention: settings.desiredRetention,
      learningSteps: [
        for (final minutes in settings.learningStepsMinutes)
          Duration(minutes: minutes),
      ],
      relearningSteps: [
        for (final minutes in settings.relearningStepsMinutes)
          Duration(minutes: minutes),
      ],
      enableFuzzing: enableFuzzing,
    );
  }

  Card _toFsrsCard(CardItem card, DateTime nowUtc) {
    if (card.isNew) {
      return Card(
        cardId: card.id.hashCode,
        state: State.learning,
        step: 0,
        due: nowUtc,
      );
    }
    return Card(
      cardId: card.id.hashCode,
      state: State.fromValue(card.state.index),
      step: card.step,
      stability: card.stability,
      difficulty: card.difficulty,
      due: card.due?.toUtc() ?? nowUtc,
      lastReview: card.lastReview?.toUtc(),
    );
  }

  CardLearningState _toCardState(State state) =>
      CardLearningState.fromIndex(state.value);

  /// Applies [rating] and returns the rescheduled card plus a review log.
  ///
  /// The returned card is a new instance; [card] is never mutated.
  ScheduledReview schedule({
    required CardItem card,
    required Rating rating,
    required AppSettings settings,
    StudyMode mode = StudyMode.srs,
    DateTime? now,
    int durationMs = 0,
  }) {
    final reviewDateTime = (now ?? DateTime.now()).toUtc();
    final scheduler = createScheduler(settings);
    final result = scheduler.reviewCard(
      _toFsrsCard(card, reviewDateTime),
      rating,
      reviewDateTime: reviewDateTime,
      reviewDuration: durationMs,
    );

    final newDue = result.card.due.toLocal();
    final interval = result.card.due.difference(reviewDateTime);
    final wasLapse =
        rating == Rating.again && (card.isReview || card.isRelearning);

    final updatedCard = card.copyWith(
      state: _toCardState(result.card.state),
      step: result.card.step,
      stability: result.card.stability,
      difficulty: result.card.difficulty,
      due: newDue,
      lastReview: reviewDateTime.toLocal(),
      reps: card.reps + 1,
      lapses: card.lapses + (wasLapse ? 1 : 0),
      updatedAt: reviewDateTime.toLocal(),
    );

    final log = ReviewLog(
      cardId: card.id,
      collectionId: card.collectionId,
      rating: rating.value,
      reviewedAt: reviewDateTime.toLocal(),
      durationMs: durationMs,
      mode: mode.name,
      previousState: card.state.index,
      previousDue: card.due,
      scheduledDays: interval.inDays,
    );

    return ScheduledReview(card: updatedCard, log: log, interval: interval);
  }

  /// Creates a log for a practice mode without touching scheduling fields.
  ReviewLog practiceLog({
    required CardItem card,
    required Rating rating,
    required StudyMode mode,
    DateTime? now,
    int durationMs = 0,
  }) {
    final reviewedAt = now ?? DateTime.now();
    return ReviewLog(
      cardId: card.id,
      collectionId: card.collectionId,
      rating: rating.value,
      reviewedAt: reviewedAt,
      durationMs: durationMs,
      mode: mode.name,
      previousState: card.state.index,
      previousDue: card.due,
      scheduledDays: 0,
    );
  }

  /// Estimated interval for each rating button. Uses the same `now` for all
  /// ratings so the labels are comparable. Never mutates the card.
  Map<Rating, Duration> previewIntervals({
    required CardItem card,
    required AppSettings settings,
    DateTime? now,
  }) {
    final reviewTime = (now ?? DateTime.now()).toUtc();
    final scheduler = createScheduler(settings);
    final results = <Rating, Duration>{};
    for (final rating in Rating.values) {
      final result = scheduler.reviewCard(
        _toFsrsCard(card, reviewTime),
        rating,
        reviewDateTime: reviewTime,
      );
      results[rating] = result.card.due.difference(reviewTime);
    }
    return results;
  }

  /// Predicts the next due date as a local DateTime.
  DateTime? predictedDue({
    required CardItem card,
    required Rating rating,
    required AppSettings settings,
    DateTime? now,
  }) {
    final reviewTime = (now ?? DateTime.now()).toUtc();
    final scheduler = createScheduler(settings);
    final result = scheduler.reviewCard(
      _toFsrsCard(card, reviewTime),
      rating,
      reviewDateTime: reviewTime,
    );
    return result.card.due.toLocal();
  }

  /// Retrievability estimate for a reviewed card, or 0 for new cards.
  double retrievability(CardItem card, AppSettings settings) {
    if (card.isNew || card.stability == null || card.lastReview == null) {
      return 0;
    }
    final reviewTime = DateTime.now().toUtc();
    final scheduler = createScheduler(settings);
    return scheduler
        .getCardRetrievability(
          _toFsrsCard(card, reviewTime),
          currentDateTime: reviewTime,
        )
        .clamp(0.0, 1.0);
  }
}
