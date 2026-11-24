import 'package:knowit/models/card_item.dart';
import 'package:knowit/utils/id_generator.dart';

/// Identity of one independently scheduled card generated from a note.
class NoteCardSpec {
  final bool reverse;
  final int clozeIndex;

  const NoteCardSpec({this.reverse = false, this.clozeIndex = 0});

  @override
  bool operator ==(Object other) =>
      other is NoteCardSpec &&
      other.reverse == reverse &&
      other.clozeIndex == clozeIndex;

  @override
  int get hashCode => Object.hash(reverse, clozeIndex);

  @override
  String toString() => 'NoteCardSpec(reverse: $reverse, cloze: $clozeIndex)';
}

class NoteSyncPlan {
  final List<CardItem> cards;
  final List<CardItem> removed;
  final String noteId;

  const NoteSyncPlan({
    required this.cards,
    required this.removed,
    required this.noteId,
  });

  CardItem get primary => cards.first;
}

/// Pure note/card generation logic shared by the editor, AI import and Anki
/// import. Keeping it free of persistence makes sibling identity rules easy to
/// test.
class NoteService {
  const NoteService();

  /// The independently reviewable cards a note should have.
  List<NoteCardSpec> specsFor(CardType type, String frontText) {
    switch (type) {
      case CardType.basic:
        return const [NoteCardSpec()];
      case CardType.reversed:
        return const [NoteCardSpec(), NoteCardSpec(reverse: true)];
      case CardType.cloze:
        final numbers =
            RegExp(r'\{\{c(\d+)::')
                .allMatches(frontText)
                .map((match) => int.tryParse(match.group(1) ?? ''))
                .whereType<int>()
                .where((value) => value > 0)
                .toSet()
                .toList()
              ..sort();
        if (numbers.isEmpty) return const [NoteCardSpec(clozeIndex: 1)];
        return [for (final number in numbers) NoteCardSpec(clozeIndex: number)];
    }
  }

  /// Converts a pre-sibling (schema 2) card into a note group. Existing card
  /// identity and scheduling are preserved for the first generated card; extra
  /// siblings start fresh. This method is only used by the one-time migration.
  List<CardItem> migrateLegacyCard(CardItem legacy) {
    if (legacy.noteId != null) return [legacy];
    final noteId = legacy.id;
    final primary = legacy.copyWith(noteId: noteId);
    switch (legacy.type) {
      case CardType.basic:
        return [primary];
      case CardType.reversed:
        return [
          primary.copyWith(reverse: true),
          _legacySibling(primary, noteId, reverse: false),
        ];
      case CardType.cloze:
        final numbers = primary.clozeNumbers;
        if (numbers.isEmpty) return [primary];
        return [
          primary.copyWith(clozeIndex: numbers.first),
          for (final number in numbers.skip(1))
            _legacySibling(primary, noteId, clozeIndex: number),
        ];
    }
  }

  CardItem _legacySibling(
    CardItem source,
    String noteId, {
    bool? reverse,
    int? clozeIndex,
  }) {
    return CardItem(
      id: newId(),
      frontText: source.frontText,
      backText: source.backText,
      collectionId: source.collectionId,
      createdAt: source.createdAt,
      type: source.type,
      tags: List<String>.from(source.tags),
      imagePath: source.imagePath,
      audioPath: source.audioPath,
      noteId: noteId,
      reverse: reverse ?? false,
      clozeIndex: clozeIndex ?? 0,
    );
  }

  /// Produces the complete set of cards for [edited] while reusing existing
  /// sibling identities (and therefore FSRS scheduling) wherever possible.
  NoteSyncPlan plan({
    required CardItem edited,
    required List<CardItem> existing,
    required bool isNewNote,
  }) {
    final noteId = isNewNote ? edited.id : edited.noteKey;
    final specs = specsFor(edited.type, edited.frontText);
    final available = existing.where((card) => card.noteKey == noteId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final now = DateTime.now();

    final chosen = <CardItem>[];
    final usedIds = <String>{};
    final remainingSpecs = <NoteCardSpec>[];

    // Keep the card the user is currently editing as the primary identity.
    if (available.isNotEmpty) {
      final currentIndex = available.indexWhere(
        (card) =>
            card.id == edited.id &&
            card.reverse == edited.reverse &&
            card.clozeIndex == edited.clozeIndex,
      );
      final current = available.removeAt(currentIndex >= 0 ? currentIndex : 0);
      final matchingSpec = specs.firstWhere(
        (spec) =>
            spec.reverse == current.reverse &&
            spec.clozeIndex == current.clozeIndex,
        orElse: () => specs.first,
      );
      remainingSpecs.addAll(specs.where((spec) => spec != matchingSpec));
      chosen.add(_updated(current, edited, noteId, matchingSpec, now));
      usedIds.add(current.id);
    } else {
      remainingSpecs.addAll(specs);
    }

    for (final spec in remainingSpecs) {
      final matchIndex = available.indexWhere(
        (card) =>
            !usedIds.contains(card.id) &&
            card.reverse == spec.reverse &&
            card.clozeIndex == spec.clozeIndex,
      );
      if (matchIndex >= 0) {
        final card = available.removeAt(matchIndex);
        usedIds.add(card.id);
        chosen.add(_updated(card, edited, noteId, spec, now));
      } else {
        // Reuse an unrelated sibling to preserve its review history when the
        // note type or cloze numbering changes, as long as it still exists.
        final reusableIndex = available.indexWhere(
          (card) => !usedIds.contains(card.id),
        );
        if (reusableIndex >= 0) {
          final card = available.removeAt(reusableIndex);
          usedIds.add(card.id);
          chosen.add(_updated(card, edited, noteId, spec, now));
        } else {
          chosen.add(
            _fresh(
              edited,
              noteId,
              spec,
              now,
              id: isNewNote && chosen.isEmpty ? edited.id : null,
            ),
          );
        }
      }
    }

    final removed = available
        .where((card) => !usedIds.contains(card.id))
        .toList();

    // Keep the edited card first so callers can return it to the UI.
    chosen.sort((a, b) {
      if (a.id == edited.id) return -1;
      if (b.id == edited.id) return 1;
      final reverse = a.reverse.toString().compareTo(b.reverse.toString());
      if (reverse != 0) return reverse;
      return a.clozeIndex.compareTo(b.clozeIndex);
    });

    return NoteSyncPlan(cards: chosen, removed: removed, noteId: noteId);
  }

  CardItem _updated(
    CardItem target,
    CardItem source,
    String noteId,
    NoteCardSpec spec,
    DateTime now,
  ) {
    return target.copyWith(
      frontText: source.frontText,
      backText: source.backText,
      collectionId: source.collectionId,
      type: source.type,
      tags: List<String>.from(source.tags),
      imagePath: source.imagePath,
      audioPath: source.audioPath,
      noteId: noteId,
      reverse: spec.reverse,
      clozeIndex: spec.clozeIndex,
      updatedAt: now,
    );
  }

  CardItem _fresh(
    CardItem source,
    String noteId,
    NoteCardSpec spec,
    DateTime now, {
    String? id,
  }) {
    return CardItem(
      id: id ?? newId(),
      frontText: source.frontText,
      backText: source.backText,
      collectionId: source.collectionId,
      createdAt: now,
      updatedAt: now,
      type: source.type,
      tags: List<String>.from(source.tags),
      imagePath: source.imagePath,
      audioPath: source.audioPath,
      noteId: noteId,
      reverse: spec.reverse,
      clozeIndex: spec.clozeIndex,
    );
  }
}
