import 'package:knowit/models/card_item.dart';
import 'package:knowit/services/ai/ai_models.dart';
import 'package:knowit/services/html_markup.dart';

/// Local duplicate detection. This never calls an AI provider, so it also
/// works offline and cannot fabricate matches.
class DuplicateDetector {
  const DuplicateDetector();

  String _cardKey(CardItem card) {
    if (card.isCloze) {
      return 'cloze:${normalizeForDuplicate(card.frontText)}';
    }
    final front = normalizeForDuplicate(card.frontText);
    final back = normalizeForDuplicate(card.backText);
    final a = '$front|$back';
    final b = '$back|$front';
    return a.compareTo(b) <= 0 ? 'std:$a' : 'std:$b';
  }

  String _generatedKey(AiGeneratedCard card) {
    if (card.type == CardType.cloze) {
      return 'cloze:${normalizeForDuplicate(card.front)}';
    }
    final front = normalizeForDuplicate(card.front);
    final back = normalizeForDuplicate(card.back);
    final a = '$front|$back';
    final b = '$back|$front';
    return a.compareTo(b) <= 0 ? 'std:$a' : 'std:$b';
  }

  /// Returns one duplicate flag per generated card. A card is flagged when it
  /// duplicates an existing note (including any sibling) or another generated
  /// card earlier in the list.
  List<bool> markDuplicates({
    required List<AiGeneratedCard> generated,
    required List<CardItem> existing,
  }) {
    final existingKeys = existing.map(_cardKey).toSet();
    final seen = <String>{};
    final flags = <bool>[];
    for (final card in generated) {
      final key = _generatedKey(card);
      final duplicate = existingKeys.contains(key) || !seen.add(key);
      flags.add(duplicate);
    }
    return flags;
  }

  Set<String> duplicateKeys({
    required List<AiGeneratedCard> generated,
    required List<CardItem> existing,
  }) {
    final flags = markDuplicates(generated: generated, existing: existing);
    return {
      for (var index = 0; index < flags.length; index++)
        if (flags[index]) _generatedKey(generated[index]),
    };
  }
}
