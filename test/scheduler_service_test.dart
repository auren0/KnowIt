import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' show Rating;
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/services/scheduler_service.dart';

void main() {
  const scheduler = SchedulerService();
  final now = DateTime(2026, 11, 12, 9, 30);
  const settings = AppSettings(
    learningStepsMinutes: [1, 10],
    relearningStepsMinutes: [10],
    desiredRetention: 0.9,
  );

  CardItem newCard() => CardItem(
    frontText: 'Capital of France?',
    backText: 'Paris',
    collectionId: 'deck-1',
  );

  test('preview intervals increase from Again to Easy', () {
    final card = newCard();
    final previews = scheduler.previewIntervals(
      card: card,
      settings: settings,
      now: now,
    );

    expect(previews[Rating.again]!.inMinutes, 1);
    expect(previews[Rating.hard]!.inMinutes, greaterThan(1));
    expect(previews[Rating.good]!.inMinutes, 10);
    expect(previews[Rating.easy]!.inDays, greaterThanOrEqualTo(1));
    expect(
      previews[Rating.again]!.inSeconds,
      lessThan(previews[Rating.hard]!.inSeconds),
    );
  });

  test('preview never mutates the card', () {
    final card = newCard();
    scheduler.previewIntervals(card: card, settings: settings, now: now);
    expect(card.state, CardLearningState.newCard);
    expect(card.due, isNull);
    expect(card.reps, 0);
  });

  test('Good on a new card moves through the first learning step', () {
    final result = scheduler.schedule(
      card: newCard(),
      rating: Rating.good,
      settings: settings,
      now: now,
    );

    expect(result.card.state, CardLearningState.learning);
    expect(result.card.step, 1);
    expect(result.card.reps, 1);
    expect(result.card.stability, isNotNull);
    expect(result.card.difficulty, isNotNull);
    expect(result.card.due, isNotNull);
    expect(result.card.due!.isUtc, isFalse);
    expect(result.card.due!.difference(now).inSeconds, closeTo(10 * 60, 2));
    expect(result.log.rating, 3);
    expect(result.log.previousState, CardLearningState.newCard.index);
    expect(result.log.mode, StudyMode.srs.name);
  });

  test('a second Good graduates the card into review', () {
    final first = scheduler.schedule(
      card: newCard(),
      rating: Rating.good,
      settings: settings,
      now: now,
    );
    final second = scheduler.schedule(
      card: first.card,
      rating: Rating.good,
      settings: settings,
      now: now.add(const Duration(minutes: 11)),
    );

    expect(second.card.state, CardLearningState.review);
    expect(second.card.step, isNull);
    expect(second.card.due!.isAfter(now.add(const Duration(days: 1))), isTrue);
    expect(second.card.reps, 2);
  });

  test('Again on a review card enters relearning and records a lapse', () {
    final reviewCard = CardItem(
      frontText: 'Q',
      backText: 'A',
      collectionId: 'deck-1',
      state: CardLearningState.review,
      stability: 12,
      difficulty: 5,
      lastReview: now.subtract(const Duration(days: 12)),
      due: now,
      reps: 5,
      lapses: 1,
    );

    final result = scheduler.schedule(
      card: reviewCard,
      rating: Rating.again,
      settings: settings,
      now: now,
    );

    expect(result.card.state, CardLearningState.relearning);
    expect(result.card.step, 0);
    expect(result.card.reps, 6);
    expect(result.card.lapses, 2);
    expect(result.log.previousState, CardLearningState.review.index);
    expect(result.card.due!.difference(now).inMinutes, 10);
  });

  test('higher desired retention shortens review intervals', () {
    final reviewCard = CardItem(
      frontText: 'Q',
      backText: 'A',
      collectionId: 'deck-1',
      state: CardLearningState.review,
      stability: 20,
      difficulty: 4,
      lastReview: now.subtract(const Duration(days: 20)),
      due: now,
      reps: 4,
    );
    const relaxed = AppSettings(desiredRetention: 0.75);
    const strict = AppSettings(desiredRetention: 0.97);

    final relaxedPreview = scheduler.previewIntervals(
      card: reviewCard,
      settings: relaxed,
      now: now,
    )[Rating.good]!;
    final strictPreview = scheduler.previewIntervals(
      card: reviewCard,
      settings: strict,
      now: now,
    )[Rating.good]!;

    expect(strictPreview.inDays, lessThan(relaxedPreview.inDays));
  });

  test('practice logs never require scheduling data', () {
    final card = newCard();
    final log = scheduler.practiceLog(
      card: card,
      rating: Rating.good,
      mode: StudyMode.cram,
      now: now,
      durationMs: 2500,
    );

    expect(log.mode, StudyMode.cram.name);
    expect(log.wasCorrect, isTrue);
    expect(log.scheduledDays, 0);
    expect(card.state, CardLearningState.newCard);
    expect(card.reps, 0);
  });

  test('empty learning steps graduate immediately', () {
    const immediate = AppSettings(
      learningStepsMinutes: [],
      relearningStepsMinutes: [],
    );
    final result = scheduler.schedule(
      card: newCard(),
      rating: Rating.good,
      settings: immediate,
      now: now,
    );
    expect(result.card.state, CardLearningState.review);
    expect(result.card.due!.isAfter(now.add(const Duration(days: 1))), isTrue);
  });

  test('scheduling is deterministic without fuzzing', () {
    final card = newCard();
    final a = scheduler.schedule(
      card: card,
      rating: Rating.easy,
      settings: settings,
      now: now,
    );
    final b = scheduler.schedule(
      card: card,
      rating: Rating.easy,
      settings: settings,
      now: now,
    );
    expect(a.card.due, b.card.due);
    expect(a.card.stability, b.card.stability);
    expect(a.card.difficulty, b.card.difficulty);
  });
}
