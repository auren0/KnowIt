import 'dart:convert';

import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/services/ai/ai_models.dart';
import 'package:knowit/services/html_markup.dart';

const int maxAiSourceCharacters = 50000;

String buildSystemPrompt() {
  return 'You create high-quality spaced-repetition flashcards for active '
      'recall. Cards must be accurate, original, concise and unambiguous. '
      'Never invent facts that are not supported by the provided source. Do '
      'not include markdown code fences. Return JSON only.';
}

String buildGenerationPrompt(AiGenerationRequest request) {
  final format = switch (request.format) {
    CardType.basic => 'basic question/answer',
    CardType.reversed =>
      'two-sided (the same note is reviewed in both directions)',
    CardType.cloze => 'cloze deletion',
  };
  final source = request.sourceText.length > maxAiSourceCharacters
      ? request.sourceText.substring(0, maxAiSourceCharacters)
      : request.sourceText;
  final topic = request.topic.trim();

  return '''
Create exactly ${request.cardCount} flashcards from the source below.

Format: $format.
Source language: ${request.sourceLanguage}.
Output language: ${request.outputLanguage}.
${topic.isEmpty ? '' : 'Focus topic: $topic.'}

Rules:
- One discrete fact or concept per card.
- Keep fronts short and specific; answers concise but complete.
- Avoid vague prompts such as "What is this?" and avoid trivia not in the source.
- Do not repeat the same fact in multiple cards.
- Use plain text with optional **bold**, *italic* and __underline__ markup.
- For basic/reversed cards, "front" is the prompt and "back" is the answer.
- For cloze cards, "front" must contain at least one {{c1::answer}} deletion.
  Use {{c2::...}}, {{c3::...}} for additional independent deletions.
- Include 0-3 short topic tags per card, lowercase, no spaces.

Return this JSON shape and nothing else:
{"cards":[{"type":"basic|reversed|cloze","front":"...","back":"...","tags":["..."]}]}

SOURCE:
$source
''';
}

AiGenerationResult parseGenerationResponse(
  String content, {
  required AiGenerationRequest request,
}) {
  var cleaned = content.trim();
  if (cleaned.isEmpty) {
    throw AiProviderException(
      AppLocalizations.current.bi(
        'The AI provider returned an empty response.',
        'Провайдер ИИ вернул пустой ответ.',
      ),
      kind: AiErrorKind.invalidResponse,
      retryable: true,
    );
  }

  // Some compatible providers wrap JSON in markdown fences despite the prompt.
  cleaned = cleaned
      .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();

  dynamic decoded;
  try {
    decoded = jsonDecode(cleaned);
  } on FormatException {
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        decoded = jsonDecode(cleaned.substring(start, end + 1));
      } on FormatException {
        decoded = null;
      }
    }
  }

  List<dynamic>? rawCards;
  if (decoded is Map<String, dynamic> && decoded['cards'] is List) {
    rawCards = decoded['cards'] as List;
  } else if (decoded is List) {
    rawCards = decoded;
  }
  if (rawCards == null) {
    throw const AiProviderException(
      'The AI response was not valid flashcard JSON. Try again or use a model '
      'that supports structured output.',
      kind: AiErrorKind.invalidResponse,
      retryable: true,
    );
  }

  final cards = <AiGeneratedCard>[];
  final seen = <String>{};
  var skipped = 0;
  for (final item in rawCards) {
    if (item is! Map) {
      skipped++;
      continue;
    }
    final front = htmlToMarkup(item['front']?.toString() ?? '');
    final back = htmlToMarkup(item['back']?.toString() ?? '');
    if (front.trim().isEmpty) {
      skipped++;
      continue;
    }
    if (request.format == CardType.cloze) {
      if (!RegExp(r'\{\{c\d+::.+?\}\}').hasMatch(front)) {
        skipped++;
        continue;
      }
    } else if (back.trim().isEmpty) {
      skipped++;
      continue;
    }

    final tags = <String>{};
    final rawTags = item['tags'];
    if (rawTags is List) {
      for (final tag in rawTags) {
        final cleanedTag = tag
            .toString()
            .trim()
            .replaceAll(RegExp(r'\s+'), '-')
            .toLowerCase();
        if (cleanedTag.isNotEmpty && cleanedTag.length <= 40) {
          tags.add(cleanedTag);
        }
      }
    }

    final key =
        '${normalizeForDuplicate(front)}|${normalizeForDuplicate(back)}';
    if (!seen.add(key)) {
      skipped++;
      continue;
    }
    cards.add(
      AiGeneratedCard(
        front: front,
        back: request.format == CardType.cloze ? back : back,
        type: request.format,
        tags: tags.take(5).toList(),
      ),
    );
    if (cards.length >= request.cardCount) break;
  }

  if (cards.isEmpty) {
    throw AiProviderException(
      AppLocalizations.current.bi(
        'No valid flashcards were found in the AI response. Try shorter, clearer '
            'source text or a different model.',
        'В ответе ИИ не найдено корректных карточек. Попробуйте более короткий и '
            'понятный исходный текст или другую модель.',
      ),
      kind: AiErrorKind.invalidResponse,
      retryable: true,
    );
  }

  final warnings = <String>[];
  if (skipped > 0) {
    warnings.add(
      AppLocalizations.current.bi(
        '$skipped generated ${skipped == 1 ? 'entry was' : 'entries were'} '
            'discarded because they were empty, malformed or duplicated.',
        'Отброшено сгенерированных записей: $skipped (пустые, некорректные или '
            'дубликаты).',
      ),
    );
  }
  if (cards.length < request.cardCount) {
    warnings.add(
      AppLocalizations.current.bi(
        'The provider returned ${cards.length} valid '
            '${cards.length == 1 ? 'card' : 'cards'} instead of '
            '${request.cardCount}.',
        'Провайдер вернул корректных карточек: ${cards.length} вместо '
            '${request.cardCount}.',
      ),
    );
  }
  return AiGenerationResult(cards: cards, warnings: warnings);
}
