import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/services/ai/ai_models.dart';
import 'package:knowit/services/ai/openai_provider.dart';
import 'package:knowit/services/settings_service.dart';

export 'ai/ai_models.dart';

/// Process-wide AI provider configuration.
///
/// Provider metadata lives in AppSettings. The API key is kept in platform
/// secure storage and is never written to Hive, JSON backups or logs. This is
/// still client-side credential handling: for production multi-user services a
/// server-side proxy with authentication and rate limits is preferable.
class AiService {
  static const String secureKeyName = 'knowit_ai_api_key';
  static const List<String> supportedProviderIds = ['openai-compatible'];

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static AiAssistant _assistant = const DisabledAiAssistant();
  static String? _apiKey;
  static bool _initialized = false;
  static bool secureStorageAvailable = true;

  static AiAssistant get assistant => _assistant;
  static bool get isConfigured => _assistant.isConfigured;
  static String get providerName => _assistant.providerName;
  static bool get hasStoredKey => _apiKey != null && _apiKey!.isNotEmpty;

  static Future<void> init() async {
    if (_initialized) {
      _rebuild();
      return;
    }
    _initialized = true;
    try {
      _apiKey = await _storage.read(key: secureKeyName);
    } on Object {
      secureStorageAvailable = false;
      _apiKey = null;
    }
    _rebuild();
    SettingsService.notifier.removeListener(_onSettingsChanged);
    SettingsService.notifier.addListener(_onSettingsChanged);
  }

  static void _onSettingsChanged() {
    _rebuild();
  }

  static void _rebuild() {
    final settings = SettingsService.value;
    if (settings.aiProviderId != 'openai-compatible' ||
        settings.aiModel.trim().isEmpty ||
        settings.aiBaseUrl.trim().isEmpty ||
        _apiKey == null ||
        _apiKey!.trim().isEmpty) {
      _assistant = const DisabledAiAssistant();
      return;
    }
    _assistant = OpenAiCompatibleProvider(
      baseUrl: settings.aiBaseUrl,
      model: settings.aiModel,
      apiKey: _apiKey!,
    );
  }

  /// Validates and stores provider settings. Pass [apiKey] only when the user
  /// entered a new key; omit it to keep the previously stored key.
  static Future<void> configure({
    required String providerId,
    required String baseUrl,
    required String model,
    String? apiKey,
  }) async {
    final l10n = AppLocalizations.current;
    final trimmedProvider = providerId.trim();
    if (!supportedProviderIds.contains(trimmedProvider)) {
      throw AiProviderException(
        l10n.bi(
          'That AI provider is not supported by this build.',
          'Этот провайдер ИИ не поддерживается в этой сборке.',
        ),
        kind: AiErrorKind.configuration,
      );
    }
    final trimmedBase = baseUrl.trim();
    final uri = Uri.tryParse(trimmedBase);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw AiProviderException(
        l10n.bi(
          'Enter a valid provider base URL, for example '
              'https://api.openai.com/v1.',
          'Введите корректный базовый URL провайдера, например '
              'https://api.openai.com/v1.',
        ),
        kind: AiErrorKind.configuration,
      );
    }
    final isLocal =
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1' ||
        uri.host.startsWith('192.168.') ||
        uri.host.startsWith('10.');
    if (uri.scheme == 'http' && !isLocal) {
      throw AiProviderException(
        l10n.bi(
          'Use HTTPS for remote AI providers so your API key is not sent in '
              'plain text. HTTP is only accepted for localhost or a private '
              'network.',
          'Используйте HTTPS для удалённых провайдеров ИИ, чтобы ключ API не '
              'передавался открытым текстом. HTTP допускается только для '
              'localhost или частной сети.',
        ),
        kind: AiErrorKind.configuration,
      );
    }
    if (model.trim().isEmpty) {
      throw AiProviderException(
        l10n.bi(
          'Enter the model name configured for your provider.',
          'Введите название модели, настроенной у провайдера.',
        ),
        kind: AiErrorKind.configuration,
      );
    }

    final newKey = apiKey?.trim();
    if (newKey != null && newKey.isNotEmpty) {
      try {
        await _storage.write(key: secureKeyName, value: newKey);
        _apiKey = newKey;
        secureStorageAvailable = true;
      } on Object {
        secureStorageAvailable = false;
        throw AiProviderException(
          l10n.bi(
            'The API key could not be stored securely on this device. KnowIt '
                'does not fall back to insecure storage.',
            'Не удалось безопасно сохранить ключ API на этом устройстве. '
                'KnowIt не использует небезопасное хранилище.',
          ),
          kind: AiErrorKind.configuration,
        );
      }
    }

    await SettingsService.update(
      (settings) => settings.copyWith(
        aiProviderId: trimmedProvider,
        aiBaseUrl: trimmedBase,
        aiModel: model.trim(),
      ),
    );
    _rebuild();
  }

  static Future<void> clearConfiguration() async {
    try {
      await _storage.delete(key: secureKeyName);
    } on Object {
      // Clearing the in-memory key below still disables the provider.
    }
    _apiKey = null;
    await SettingsService.update((settings) => settings.copyWith(aiModel: ''));
    _rebuild();
  }

  static Future<void> testConnection() => _assistant.testConnection();

  static AppSettings get settings => SettingsService.value;
}
