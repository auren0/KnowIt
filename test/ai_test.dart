import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/services/ai/ai_models.dart';
import 'package:knowit/services/ai/ai_prompt.dart';
import 'package:knowit/services/ai/duplicate_detector.dart';
import 'package:knowit/services/ai/openai_provider.dart';

const request = AiGenerationRequest(
  sourceText: 'The mitochondria produces ATP through cellular respiration.',
  cardCount: 2,
  format: CardType.basic,
  outputLanguage: 'English',
);

void main() {
  group('AI response parsing', () {
    test('parses fenced JSON and validates cards', () {
      final result = parseGenerationResponse(
        '```json\n'
        '{"cards":[{"type":"basic","front":"What does the mitochondria do?",'
        '"back":"Produces ATP.","tags":["Biology"," energy"]}]}\n'
        '```',
        request: request,
      );

      expect(result.cards.length, 1);
      expect(result.cards.single.type, CardType.basic);
      expect(result.cards.single.tags, ['biology', 'energy']);
      expect(result.warnings, contains(contains('instead of 2')));
    });

    test('rejects malformed, empty and non-JSON responses', () {
      expect(
        () => parseGenerationResponse('not json', request: request),
        throwsA(isA<AiProviderException>()),
      );
      expect(
        () => parseGenerationResponse('{"cards":[]}', request: request),
        throwsA(isA<AiProviderException>()),
      );
    });

    test('skips invalid cloze output rather than inventing deletions', () {
      expect(
        () => parseGenerationResponse(
          '{"cards":[{"type":"cloze","front":"Paris is in France",'
          '"back":"France"}]}',
          request: const AiGenerationRequest(
            sourceText: 'France',
            cardCount: 1,
            format: CardType.cloze,
          ),
        ),
        throwsA(isA<AiProviderException>()),
      );
    });

    test('validates cloze markers and deduplicates results', () {
      final result = parseGenerationResponse(
        '{"cards":['
        '{"front":"{{c1::Paris}} is the capital of France","back":"","tags":[]},'
        '{"front":"{{c1::Paris}} is the capital of France","back":"","tags":[]},'
        '{"front":"{{c1::Berlin}} is the capital of Germany","back":"","tags":[]}'
        ']}',
        request: const AiGenerationRequest(
          sourceText: 'Capitals',
          cardCount: 3,
          format: CardType.cloze,
        ),
      );

      expect(result.cards.length, 2);
      expect(result.warnings.join(' '), contains('duplicated'));
    });
  });

  group('OpenAI-compatible provider', () {
    test(
      'sends the key, parses content and never puts the key in output',
      () async {
        late http.Request captured;
        final provider = OpenAiCompatibleProvider(
          baseUrl: 'https://example.test/v1',
          model: 'test-model',
          apiKey: 'secret-key',
          clientFactory: () => MockClient((request) async {
            captured = request;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode({
                        'cards': [
                          {
                            'type': 'basic',
                            'front': 'Question?',
                            'back': 'Answer.',
                            'tags': ['topic'],
                          },
                        ],
                      }),
                    },
                  },
                ],
              }),
              200,
            );
          }),
        );

        final result = await provider.generateCards(request);

        expect(result.cards.single.front, 'Question?');
        expect(captured.headers['Authorization'], 'Bearer secret-key');
        expect(
          captured.url.toString(),
          'https://example.test/v1/chat/completions',
        );
        expect(captured.body.contains('secret-key'), isFalse);
      },
    );

    test('maps authentication, rate limit and invalid body errors', () async {
      OpenAiCompatibleProvider providerFor(int status, String body) =>
          OpenAiCompatibleProvider(
            baseUrl: 'https://example.test/v1',
            model: 'm',
            apiKey: 'k',
            clientFactory: () =>
                MockClient((_) async => http.Response(body, status)),
          );

      await expectLater(
        providerFor(401, '{}').generateCards(request),
        throwsA(
          isA<AiProviderException>().having(
            (error) => error.kind,
            'kind',
            AiErrorKind.authentication,
          ),
        ),
      );
      await expectLater(
        providerFor(429, '{}').generateCards(request),
        throwsA(
          isA<AiProviderException>().having(
            (error) => error.kind,
            'kind',
            AiErrorKind.rateLimit,
          ),
        ),
      );
      await expectLater(
        providerFor(200, '{"unexpected": true}').generateCards(request),
        throwsA(
          isA<AiProviderException>().having(
            (error) => error.kind,
            'kind',
            AiErrorKind.invalidResponse,
          ),
        ),
      );
    });

    test('respects a pre-cancelled token', () async {
      final token = AiCancelToken()..cancel();
      final provider = OpenAiCompatibleProvider(
        baseUrl: 'https://example.test/v1',
        model: 'm',
        apiKey: 'k',
        clientFactory: () => MockClient((_) async => http.Response('{}', 200)),
      );

      expect(
        () => provider.generateCards(request, cancelToken: token),
        throwsA(isA<AiCancelledException>()),
      );
    });
  });

  group('duplicate detection', () {
    test(
      'flags duplicates against existing cards and within generated cards',
      () {
        const detector = DuplicateDetector();
        final existing = [
          CardItem(
            frontText: '**Question?**',
            backText: 'Answer.',
            collectionId: 'deck',
          ),
        ];
        final generated = [
          const AiGeneratedCard(front: 'question', back: 'answer'),
          const AiGeneratedCard(front: 'New question', back: 'New answer'),
          const AiGeneratedCard(front: 'new question', back: 'new answer'),
        ];

        final flags = detector.markDuplicates(
          generated: generated,
          existing: existing,
        );

        expect(flags, [true, false, true]);
      },
    );

    test('does not flag unrelated cards', () {
      const detector = DuplicateDetector();
      final flags = detector.markDuplicates(
        generated: const [
          AiGeneratedCard(front: 'One', back: 'First'),
          AiGeneratedCard(front: 'Two', back: 'Second'),
        ],
        existing: const [],
      );
      expect(flags, [false, false]);
    });
  });

  test('prompt includes format, language and source limits', () {
    final prompt = buildGenerationPrompt(
      const AiGenerationRequest(
        sourceText: 'Source text',
        cardCount: 4,
        format: CardType.cloze,
        outputLanguage: 'German',
      ),
    );
    expect(prompt, contains('cloze deletion'));
    expect(prompt, contains('German'));
    expect(prompt, contains('{{c1::'));
    expect(prompt, contains('exactly 4'));
  });
}
