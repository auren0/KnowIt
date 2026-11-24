import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/services/ai/ai_models.dart';
import 'package:knowit/services/ai/ai_prompt.dart';

/// OpenAI-compatible chat-completions provider.
///
/// The base URL, model and key are supplied by the user; no credentials are
/// compiled into the application. Any compatible endpoint can be used by
/// changing the base URL in Settings.
class OpenAiCompatibleProvider implements AiAssistant {
  final String baseUrl;
  final String model;
  final String apiKey;
  final Duration timeout;
  final http.Client Function()? clientFactory;

  const OpenAiCompatibleProvider({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.timeout = const Duration(seconds: 90),
    this.clientFactory,
  });

  @override
  String get id => 'openai-compatible';

  @override
  String get providerName => model.isEmpty ? 'OpenAI-compatible' : model;

  @override
  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty;

  Uri _endpoint(String suffix) {
    var root = baseUrl.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    if (root.endsWith('/chat/completions') && suffix == 'chat/completions') {
      return Uri.parse(root);
    }
    return Uri.parse('$root/$suffix');
  }

  @override
  Future<AiGenerationResult> generateCards(
    AiGenerationRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    final l10n = AppLocalizations.current;
    if (!isConfigured) {
      throw AiProviderException(
        l10n.bi(
          'AI provider is not fully configured. Add a base URL, model and API '
              'key in Settings.',
          'Провайдер ИИ настроен не полностью. Добавьте базовый URL, модель и '
              'ключ API в настройках.',
        ),
        kind: AiErrorKind.configuration,
      );
    }
    if (!request.isValid) {
      throw AiProviderException(
        l10n.bi(
          'Add source text and choose a card count between 1 and 100.',
          'Добавьте исходный текст и выберите количество карточек от 1 до 100.',
        ),
        kind: AiErrorKind.configuration,
      );
    }
    cancelToken?.throwIfCancelled();

    final body = <String, dynamic>{
      'model': model,
      'temperature': 0.25,
      'messages': [
        {'role': 'system', 'content': buildSystemPrompt()},
        {'role': 'user', 'content': buildGenerationPrompt(request)},
      ],
      'response_format': {'type': 'json_object'},
    };

    final response = await _postChat(body, cancelToken: cancelToken);
    final content = _extractContent(response);
    return parseGenerationResponse(content, request: request);
  }

  Future<http.Response> _postChat(
    Map<String, dynamic> body, {
    AiCancelToken? cancelToken,
  }) async {
    final client = clientFactory?.call() ?? http.Client();
    void closeClient() {
      try {
        client.close();
      } on Object {
        // Already closed.
      }
    }

    cancelToken?.addListener(closeClient);
    final l10n = AppLocalizations.current;
    try {
      cancelToken?.throwIfCancelled();
      var response = await client
          .post(
            _endpoint('chat/completions'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (response.statusCode == 400 &&
          body.containsKey('response_format') &&
          (response.body.toLowerCase().contains('response_format') ||
              response.body.toLowerCase().contains('json'))) {
        // Some compatible providers do not support structured output. Retry
        // once without it; the prompt still requires JSON and the parser is
        // defensive.
        final fallback = Map<String, dynamic>.from(body)
          ..remove('response_format');
        response = await client
            .post(
              _endpoint('chat/completions'),
              headers: _headers,
              body: jsonEncode(fallback),
            )
            .timeout(timeout);
      }
      cancelToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _errorForResponse(response);
      }
      return response;
    } on TimeoutException {
      throw AiProviderException(
        l10n.bi(
          'The AI provider took too long to respond. Try again with less text '
              'or a faster model.',
          'Провайдер ИИ слишком долго отвечал. Повторите с меньшим объёмом '
              'текста или более быстрой моделью.',
        ),
        kind: AiErrorKind.timeout,
        retryable: true,
      );
    } on http.ClientException catch (error) {
      if (cancelToken?.isCancelled == true) {
        throw AiCancelledException();
      }
      throw AiProviderException(
        l10n.bi(
          'Could not reach the AI provider. Check your connection and base URL. '
              '(${error.message})',
          'Не удалось связаться с провайдером ИИ. Проверьте подключение и '
              'базовый URL. (${error.message})',
        ),
        kind: AiErrorKind.network,
        retryable: true,
      );
    } on AiProviderException {
      rethrow;
    } on Object catch (error) {
      if (cancelToken?.isCancelled == true) {
        throw AiCancelledException();
      }
      throw AiProviderException(
        l10n.bi(
          'The AI request failed: $error',
          'Запрос к ИИ завершился ошибкой: $error',
        ),
        kind: AiErrorKind.network,
        retryable: true,
      );
    } finally {
      cancelToken?.removeListener(closeClient);
      closeClient();
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${apiKey.trim()}',
  };

  AiProviderException _errorForResponse(http.Response response) {
    final l10n = AppLocalizations.current;
    final status = response.statusCode;
    final detail = _safeErrorDetail(response.body);
    if (status == 401 || status == 403) {
      return AiProviderException(
        l10n.bi(
          'The AI provider rejected the API key. Check the key in Settings.'
              '${detail.isEmpty ? '' : ' $detail'}',
          'Провайдер ИИ отклонил ключ API. Проверьте ключ в настройках.'
              '${detail.isEmpty ? '' : ' $detail'}',
        ),
        kind: AiErrorKind.authentication,
      );
    }
    if (status == 429) {
      return AiProviderException(
        l10n.bi(
          'The AI provider rate limit was reached. Wait a moment and retry.'
              '${detail.isEmpty ? '' : ' $detail'}',
          'Достигнут лимит запросов провайдера ИИ. Подождите и повторите.'
              '${detail.isEmpty ? '' : ' $detail'}',
        ),
        kind: AiErrorKind.rateLimit,
        retryable: true,
      );
    }
    if (status >= 500 || status == 408) {
      return AiProviderException(
        l10n.bi(
          'The AI provider is temporarily unavailable (HTTP $status).'
              '${detail.isEmpty ? '' : ' $detail'}',
          'Провайдер ИИ временно недоступен (HTTP $status).'
              '${detail.isEmpty ? '' : ' $detail'}',
        ),
        kind: AiErrorKind.network,
        retryable: true,
      );
    }
    return AiProviderException(
      l10n.bi(
        'The AI provider returned HTTP $status.'
            '${detail.isEmpty ? '' : ' $detail'}',
        'Провайдер ИИ вернул HTTP $status.'
            '${detail.isEmpty ? '' : ' $detail'}',
      ),
      kind: AiErrorKind.unknown,
    );
  }

  String _safeErrorDetail(String body) {
    var text = body.trim();
    if (text.isEmpty) return '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          text = error['message'] as String;
        } else if (decoded['message'] is String) {
          text = decoded['message'] as String;
        }
      }
    } on FormatException {
      // Use the original text.
    }
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 240 ? '${text.substring(0, 240)}…' : text;
  }

  String _extractContent(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Expected an object');
      }
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        throw const FormatException('Missing choices');
      }
      final message = (choices.first as Map)['message'];
      if (message is! Map) throw const FormatException('Missing message');
      final content = message['content'];
      if (content is String) return content;
      if (content is List) {
        final parts = <String>[];
        for (final part in content) {
          if (part is Map && part['text'] is String) {
            parts.add(part['text'] as String);
          }
        }
        if (parts.isNotEmpty) return parts.join('\n');
      }
      throw const FormatException('Missing content');
    } on FormatException {
      throw AiProviderException(
        AppLocalizations.current.bi(
          'The AI provider returned an unexpected response shape.',
          'Провайдер ИИ вернул ответ неожиданной структуры.',
        ),
        kind: AiErrorKind.invalidResponse,
        retryable: true,
      );
    }
  }

  @override
  Future<void> testConnection() async {
    final l10n = AppLocalizations.current;
    if (!isConfigured) {
      throw AiProviderException(
        l10n.bi(
          'Add a base URL, model and API key before testing the connection.',
          'Добавьте базовый URL, модель и ключ API перед проверкой подключения.',
        ),
        kind: AiErrorKind.configuration,
      );
    }
    final client = clientFactory?.call() ?? http.Client();
    try {
      final response = await client
          .get(_endpoint('models'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw _errorForResponse(response);
      }
      if (response.statusCode >= 200 && response.statusCode < 300) return;
      if (response.statusCode == 404) {
        throw AiProviderException(
          l10n.bi(
            'The provider is reachable, but the models endpoint was not found. '
                'The base URL may be incomplete (for example it usually ends in /v1).',
            'Провайдер доступен, но endpoint моделей не найден. Базовый URL '
                'может быть неполным (обычно он заканчивается на /v1).',
          ),
          kind: AiErrorKind.configuration,
        );
      }
      throw _errorForResponse(response);
    } on TimeoutException {
      throw AiProviderException(
        l10n.bi(
          'The connection test timed out.',
          'Время проверки подключения истекло.',
        ),
        kind: AiErrorKind.timeout,
        retryable: true,
      );
    } on http.ClientException catch (error) {
      throw AiProviderException(
        l10n.bi(
          'Could not reach the provider: ${error.message}',
          'Не удалось связаться с провайдером: ${error.message}',
        ),
        kind: AiErrorKind.network,
        retryable: true,
      );
    } finally {
      client.close();
    }
  }
}
