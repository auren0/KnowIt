import 'dart:async';

import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/card_item.dart';

/// A card proposed by an AI provider before the user saves it.
class AiGeneratedCard {
  final String front;
  final String back;
  final CardType type;
  final List<String> tags;

  const AiGeneratedCard({
    required this.front,
    required this.back,
    this.type = CardType.basic,
    this.tags = const [],
  });

  AiGeneratedCard copyWith({
    String? front,
    String? back,
    CardType? type,
    List<String>? tags,
  }) {
    return AiGeneratedCard(
      front: front ?? this.front,
      back: back ?? this.back,
      type: type ?? this.type,
      tags: tags ?? this.tags,
    );
  }
}

class AiGenerationRequest {
  final String sourceText;
  final String topic;
  final int cardCount;
  final CardType format;
  final String sourceLanguage;
  final String outputLanguage;

  const AiGenerationRequest({
    required this.sourceText,
    required this.cardCount,
    this.topic = '',
    this.format = CardType.basic,
    this.sourceLanguage = 'Auto-detect',
    this.outputLanguage = 'English',
  });

  bool get isValid =>
      sourceText.trim().isNotEmpty && cardCount > 0 && cardCount <= 100;
}

class AiGenerationResult {
  final List<AiGeneratedCard> cards;
  final List<String> warnings;

  const AiGenerationResult({required this.cards, this.warnings = const []});
}

enum AiErrorKind {
  configuration,
  authentication,
  rateLimit,
  network,
  timeout,
  invalidResponse,
  cancelled,
  unknown,
}

class AiProviderException implements Exception {
  final String message;
  final AiErrorKind kind;
  final bool retryable;

  const AiProviderException(
    this.message, {
    this.kind = AiErrorKind.unknown,
    this.retryable = false,
  });

  @override
  String toString() => message;
}

class AiCancelledException extends AiProviderException {
  AiCancelledException()
    : super(
        AppLocalizations.current.bi(
          'Generation cancelled.',
          'Генерация отменена.',
        ),
        kind: AiErrorKind.cancelled,
      );
}

/// Cooperative cancellation shared by the UI and HTTP provider.
class AiCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<void Function()>.from(_listeners)) {
      try {
        listener();
      } on Object {
        // Cancellation listeners must never break the app.
      }
    }
    _listeners.clear();
  }

  void throwIfCancelled() {
    if (_cancelled) throw AiCancelledException();
  }
}

/// Provider-independent AI contract. Additional providers can implement this
/// interface without changing the generation screen or persistence layer.
abstract interface class AiAssistant {
  String get id;
  String get providerName;
  bool get isConfigured;

  Future<AiGenerationResult> generateCards(
    AiGenerationRequest request, {
    AiCancelToken? cancelToken,
  });

  Future<void> testConnection();
}

class DisabledAiAssistant implements AiAssistant {
  const DisabledAiAssistant();

  @override
  String get id => 'none';

  @override
  bool get isConfigured => false;

  @override
  String get providerName =>
      AppLocalizations.current.bi('Not configured', 'Не настроено');

  @override
  Future<AiGenerationResult> generateCards(
    AiGenerationRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    throw AiProviderException(
      AppLocalizations.current.bi(
        'No AI provider is configured. Add a provider in Settings first.',
        'Провайдер ИИ не настроен. Сначала добавьте провайдера в настройках.',
      ),
      kind: AiErrorKind.configuration,
    );
  }

  @override
  Future<void> testConnection() async {
    throw AiProviderException(
      AppLocalizations.current.bi(
        'No AI provider is configured.',
        'Провайдер ИИ не настроен.',
      ),
      kind: AiErrorKind.configuration,
    );
  }
}
