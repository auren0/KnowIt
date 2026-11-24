import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/services/note_service.dart';

void main() {
  const service = NoteService();

  test('basic notes generate one card', () {
    final note = CardItem(
      frontText: 'Question',
      backText: 'Answer',
      collectionId: 'deck',
      type: CardType.basic,
    );
    final plan = service.plan(
      edited: note,
      existing: const [],
      isNewNote: true,
    );

    expect(plan.cards.length, 1);
    expect(plan.cards.single.reverse, isFalse);
    expect(plan.cards.single.noteId, note.id);
    expect(plan.cards.single.id, note.id);
    expect(plan.removed, isEmpty);
  });

  test('reversed notes generate two independently identified cards', () {
    final note = CardItem(
      frontText: 'bonjour',
      backText: 'hello',
      collectionId: 'deck',
      type: CardType.reversed,
    );
    final plan = service.plan(
      edited: note,
      existing: const [],
      isNewNote: true,
    );

    expect(plan.cards.length, 2);
    expect(plan.cards.map((card) => card.reverse).toSet(), {false, true});
    expect(plan.cards.map((card) => card.id).toSet().length, 2);
    expect(plan.cards.map((card) => card.noteId).toSet(), {note.id});
    expect(plan.primary.id, note.id);
    expect(plan.cards.first.studyFront, 'bonjour');
    expect(plan.cards.last.studyFront, 'hello');
  });

  test('cloze notes generate one card per deletion number', () {
    final note = CardItem(
      frontText:
          'The capital of France is {{c1::Paris}} and Germany is '
          '{{c2::Berlin}}.',
      backText: 'European capitals',
      collectionId: 'deck',
      type: CardType.cloze,
    );
    final plan = service.plan(
      edited: note,
      existing: const [],
      isNewNote: true,
    );

    expect(plan.cards.length, 2);
    expect(plan.cards.map((card) => card.clozeIndex).toSet(), {1, 2});
    expect(plan.cards.first.studyFront.contains('Paris'), isFalse);
    expect(plan.cards.first.studyFront.contains('Berlin'), isTrue);
    expect(plan.cards.last.studyFront.contains('Berlin'), isFalse);
    expect(plan.cards.last.studyBack.contains('Berlin'), isTrue);
  });

  test('editing a note preserves sibling ids and scheduling', () {
    final note = CardItem(
      frontText: 'Front',
      backText: 'Back',
      collectionId: 'deck',
      type: CardType.reversed,
    );
    final initial = service
        .plan(edited: note, existing: const [], isNewNote: true)
        .cards;
    final scheduled = [
      initial.first.copyWith(
        state: CardLearningState.review,
        stability: 9.0,
        difficulty: 4.0,
        due: DateTime(2027, 1, 1),
        reps: 4,
      ),
      initial.last.copyWith(
        state: CardLearningState.learning,
        step: 1,
        due: DateTime(2026, 12, 1),
        reps: 1,
      ),
    ];
    final edited = scheduled.first.copyWith(
      frontText: 'New front',
      backText: 'New back',
    );

    final plan = service.plan(
      edited: edited,
      existing: scheduled,
      isNewNote: false,
    );

    expect(plan.cards.length, 2);
    expect(plan.cards.map((card) => card.id).toSet(), {
      scheduled.first.id,
      scheduled.last.id,
    });
    for (final card in plan.cards) {
      expect(card.frontText, 'New front');
      expect(card.backText, 'New back');
    }
    final preserved = plan.cards.firstWhere(
      (card) => card.id == scheduled.first.id,
    );
    expect(preserved.stability, 9);
    expect(preserved.reps, 4);
    expect(plan.removed, isEmpty);
  });

  test('removing a cloze deletion removes only its obsolete card', () {
    final note = CardItem(
      frontText: '{{c1::One}} and {{c2::Two}}',
      backText: '',
      collectionId: 'deck',
      type: CardType.cloze,
    );
    final existing = service
        .plan(edited: note, existing: const [], isNewNote: true)
        .cards;
    final edited = existing.first.copyWith(frontText: '{{c1::One}} only');

    final plan = service.plan(
      edited: edited,
      existing: existing,
      isNewNote: false,
    );

    expect(plan.cards.length, 1);
    expect(plan.cards.single.clozeIndex, 1);
    expect(plan.removed.length, 1);
  });

  test('legacy reversed and cloze cards migrate into sibling groups', () {
    final legacyReversed = CardItem(
      frontText: 'bonjour',
      backText: 'hello',
      collectionId: 'deck',
      type: CardType.reversed,
      state: CardLearningState.review,
      stability: 7.5,
      reps: 3,
    );
    final migratedReversed = service.migrateLegacyCard(legacyReversed);
    expect(migratedReversed.length, 2);
    expect(migratedReversed.first.id, legacyReversed.id);
    expect(migratedReversed.first.stability, 7.5);
    expect(migratedReversed.first.reverse, isTrue);
    expect(migratedReversed.last.reverse, isFalse);
    expect(migratedReversed.map((card) => card.noteId).toSet(), {
      legacyReversed.id,
    });

    final legacyCloze = CardItem(
      frontText: '{{c1::Paris}} and {{c2::Berlin}}',
      backText: '',
      collectionId: 'deck',
      type: CardType.cloze,
      state: CardLearningState.review,
      stability: 4,
      reps: 2,
    );
    final migratedCloze = service.migrateLegacyCard(legacyCloze);
    expect(migratedCloze.length, 2);
    expect(migratedCloze.map((card) => card.clozeIndex), [1, 2]);
    expect(migratedCloze.first.id, legacyCloze.id);
    expect(migratedCloze.first.stability, 4);
  });

  test('changing basic to reversed keeps the original card identity', () {
    final note = CardItem(
      frontText: 'Front',
      backText: 'Back',
      collectionId: 'deck',
      type: CardType.basic,
    );
    final basicPlan = service.plan(
      edited: note,
      existing: const [],
      isNewNote: true,
    );
    final existing = basicPlan.cards
        .map(
          (card) => card.copyWith(
            state: CardLearningState.review,
            stability: 3.0,
            reps: 2,
          ),
        )
        .toList();
    final edited = existing.single.copyWith(type: CardType.reversed);

    final plan = service.plan(
      edited: edited,
      existing: existing,
      isNewNote: false,
    );

    expect(plan.cards.length, 2);
    expect(plan.cards.any((card) => card.id == existing.single.id), isTrue);
    final preserved = plan.cards.firstWhere(
      (card) => card.id == existing.single.id,
    );
    expect(preserved.stability, 3);
  });
}
