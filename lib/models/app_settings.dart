import 'package:flutter/material.dart';

/// Application language. English is the default regardless of the device
/// locale; an explicit user choice is persisted in the settings box.
enum AppLanguage {
  en('en', 'English'),
  ru('ru', 'Русский');

  const AppLanguage(this.code, this.nativeLabel);

  final String code;
  final String nativeLabel;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) => AppLanguage.values.firstWhere(
    (value) => value.code == code,
    orElse: () => AppLanguage.en,
  );
}

/// Global accent palette. The default yellow keeps the KnowIt identity.
enum AccentColor {
  yellow('Yellow', Color(0xFFF2B705)),
  blue('Blue', Color(0xFF2F6FED)),
  green('Green', Color(0xFF2E9E5B)),
  purple('Purple', Color(0xFF7A4FE0)),
  orange('Orange', Color(0xFFE8730C)),
  red('Red', Color(0xFFE53935)),
  pink('Pink', Color(0xFFD81B60)),
  cyan('Cyan', Color(0xFF00ACC1)),
  teal('Teal', Color(0xFF00897B)),
  indigo('Indigo', Color(0xFF3949AB)),
  mint('Mint', Color(0xFF10B981)),
  coral('Coral', Color(0xFFFF6F61));

  const AccentColor(this.storageName, this.seed);

  final String storageName;
  final Color seed;

  static AccentColor fromName(String? name) => AccentColor.values.firstWhere(
    (value) =>
        value.name == name ||
        value.storageName.toLowerCase() == name?.toLowerCase(),
    orElse: () => AccentColor.yellow,
  );
}

/// Bundled typefaces. Nunito is the default; JetBrains Mono is optional.
enum AppFontFamily {
  nunito('Nunito'),
  jetBrainsMono('JetBrainsMono');

  const AppFontFamily(this.family);

  final String family;

  static AppFontFamily fromName(String? name) =>
      AppFontFamily.values.firstWhere(
        (value) => value.name == name,
        orElse: () => AppFontFamily.nunito,
      );
}

/// How a flashcard answer is revealed during study.
enum AnswerRevealMode {
  /// Smooth 3D card rotation (the historical KnowIt behaviour).
  flip,

  /// Immediate content swap with no rotation, like Anki.
  instant;

  static AnswerRevealMode fromName(String? name) =>
      AnswerRevealMode.values.firstWhere(
        (value) => value.name == name,
        orElse: () => AnswerRevealMode.flip,
      );
}

/// Theme preference persisted in the settings box.
enum ThemePreference {
  system,
  light,
  dark;

  ThemeMode get materialMode => switch (this) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
  };

  String get label => switch (this) {
    ThemePreference.system => 'System',
    ThemePreference.light => 'Light',
    ThemePreference.dark => 'Dark',
  };

  static ThemePreference fromName(String? name) =>
      ThemePreference.values.firstWhere(
        (value) => value.name == name,
        orElse: () => ThemePreference.system,
      );
}

/// Immutable application settings. Persisted as a primitive map in Hive so
/// adding a field never breaks older installations.
class AppSettings {
  final ThemePreference theme;
  final int newCardsPerDay;
  final int reviewsPerDay;
  final double desiredRetention;
  final List<int> learningStepsMinutes;
  final List<int> relearningStepsMinutes;
  final int dailyGoal;
  final bool remindersEnabled;
  final int reminderHour;
  final int reminderMinute;
  final bool swipeToRate;
  final bool animationsEnabled;
  final double textScale;
  final bool keyboardShortcuts;
  final bool hapticFeedback;
  final String aiProviderId;
  final String aiBaseUrl;
  final String aiModel;
  final String aiSourceLanguage;
  final String aiOutputLanguage;
  final AppLanguage language;
  final AccentColor accentColor;
  final AppFontFamily fontFamily;
  final AnswerRevealMode answerRevealMode;

  const AppSettings({
    this.theme = ThemePreference.system,
    this.newCardsPerDay = 20,
    this.reviewsPerDay = 200,
    this.desiredRetention = 0.9,
    this.learningStepsMinutes = const [1, 10],
    this.relearningStepsMinutes = const [10],
    this.dailyGoal = 50,
    this.remindersEnabled = false,
    this.reminderHour = 20,
    this.reminderMinute = 0,
    this.swipeToRate = true,
    this.animationsEnabled = true,
    this.textScale = 1.0,
    this.keyboardShortcuts = true,
    this.hapticFeedback = true,
    this.aiProviderId = 'openai-compatible',
    this.aiBaseUrl = 'https://api.openai.com/v1',
    this.aiModel = '',
    this.aiSourceLanguage = 'Auto-detect',
    this.aiOutputLanguage = 'English',
    this.language = AppLanguage.en,
    this.accentColor = AccentColor.yellow,
    this.fontFamily = AppFontFamily.nunito,
    this.answerRevealMode = AnswerRevealMode.flip,
  });

  static const AppSettings defaults = AppSettings();

  bool get learningStepsEnabled => learningStepsMinutes.isNotEmpty;

  Duration get learningStepDuration => Duration(
    minutes: learningStepsMinutes.isNotEmpty ? learningStepsMinutes.first : 1,
  );

  AppSettings copyWith({
    ThemePreference? theme,
    int? newCardsPerDay,
    int? reviewsPerDay,
    double? desiredRetention,
    List<int>? learningStepsMinutes,
    List<int>? relearningStepsMinutes,
    int? dailyGoal,
    bool? remindersEnabled,
    int? reminderHour,
    int? reminderMinute,
    bool? swipeToRate,
    bool? animationsEnabled,
    double? textScale,
    bool? keyboardShortcuts,
    bool? hapticFeedback,
    String? aiProviderId,
    String? aiBaseUrl,
    String? aiModel,
    String? aiSourceLanguage,
    String? aiOutputLanguage,
    AppLanguage? language,
    AccentColor? accentColor,
    AppFontFamily? fontFamily,
    AnswerRevealMode? answerRevealMode,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      newCardsPerDay: newCardsPerDay ?? this.newCardsPerDay,
      reviewsPerDay: reviewsPerDay ?? this.reviewsPerDay,
      desiredRetention: desiredRetention ?? this.desiredRetention,
      learningStepsMinutes: learningStepsMinutes ?? this.learningStepsMinutes,
      relearningStepsMinutes:
          relearningStepsMinutes ?? this.relearningStepsMinutes,
      dailyGoal: dailyGoal ?? this.dailyGoal,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      swipeToRate: swipeToRate ?? this.swipeToRate,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      textScale: textScale ?? this.textScale,
      keyboardShortcuts: keyboardShortcuts ?? this.keyboardShortcuts,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      aiProviderId: aiProviderId ?? this.aiProviderId,
      aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
      aiModel: aiModel ?? this.aiModel,
      aiSourceLanguage: aiSourceLanguage ?? this.aiSourceLanguage,
      aiOutputLanguage: aiOutputLanguage ?? this.aiOutputLanguage,
      language: language ?? this.language,
      accentColor: accentColor ?? this.accentColor,
      fontFamily: fontFamily ?? this.fontFamily,
      answerRevealMode: answerRevealMode ?? this.answerRevealMode,
    );
  }

  Map<String, dynamic> toMap() => {
    'theme': theme.name,
    'newCardsPerDay': newCardsPerDay,
    'reviewsPerDay': reviewsPerDay,
    'desiredRetention': desiredRetention,
    'learningStepsMinutes': learningStepsMinutes,
    'relearningStepsMinutes': relearningStepsMinutes,
    'dailyGoal': dailyGoal,
    'remindersEnabled': remindersEnabled,
    'reminderHour': reminderHour,
    'reminderMinute': reminderMinute,
    'swipeToRate': swipeToRate,
    'animationsEnabled': animationsEnabled,
    'textScale': textScale,
    'keyboardShortcuts': keyboardShortcuts,
    'hapticFeedback': hapticFeedback,
    'aiProviderId': aiProviderId,
    'aiBaseUrl': aiBaseUrl,
    'aiModel': aiModel,
    'aiSourceLanguage': aiSourceLanguage,
    'aiOutputLanguage': aiOutputLanguage,
    'language': language.code,
    'accentColor': accentColor.name,
    'fontFamily': fontFamily.name,
    'answerRevealMode': answerRevealMode.name,
  };

  factory AppSettings.fromMap(Map<dynamic, dynamic> map) {
    final learning = _steps(
      map['learningStepsMinutes'],
      fallback: defaults.learningStepsMinutes,
    );
    final relearning = _steps(
      map['relearningStepsMinutes'],
      fallback: defaults.relearningStepsMinutes,
    );
    return AppSettings(
      theme: ThemePreference.fromName(map['theme'] as String?),
      newCardsPerDay: _clampInt(
        map['newCardsPerDay'],
        defaults.newCardsPerDay,
        0,
        1000,
      ),
      reviewsPerDay: _clampInt(
        map['reviewsPerDay'],
        defaults.reviewsPerDay,
        0,
        5000,
      ),
      desiredRetention: _clampDouble(
        map['desiredRetention'],
        defaults.desiredRetention,
        0.7,
        0.99,
      ),
      learningStepsMinutes: learning,
      relearningStepsMinutes: relearning,
      dailyGoal: _clampInt(map['dailyGoal'], defaults.dailyGoal, 0, 1000),
      remindersEnabled: map['remindersEnabled'] as bool? ?? false,
      reminderHour: _clampInt(map['reminderHour'], 20, 0, 23),
      reminderMinute: _clampInt(map['reminderMinute'], 0, 0, 59),
      swipeToRate: map['swipeToRate'] as bool? ?? true,
      animationsEnabled: map['animationsEnabled'] as bool? ?? true,
      textScale: _clampDouble(map['textScale'], 1.0, 0.8, 1.5),
      keyboardShortcuts: map['keyboardShortcuts'] as bool? ?? true,
      hapticFeedback: map['hapticFeedback'] as bool? ?? true,
      aiProviderId: (map['aiProviderId'] as String?)?.trim().isNotEmpty == true
          ? (map['aiProviderId'] as String).trim()
          : 'openai-compatible',
      aiBaseUrl: _stringOr(map['aiBaseUrl'], 'https://api.openai.com/v1'),
      aiModel: (map['aiModel'] as String?)?.trim() ?? '',
      aiSourceLanguage: _stringOr(map['aiSourceLanguage'], 'Auto-detect'),
      aiOutputLanguage: _stringOr(map['aiOutputLanguage'], 'English'),
      language: AppLanguage.fromCode(map['language'] as String?),
      accentColor: AccentColor.fromName(map['accentColor'] as String?),
      fontFamily: AppFontFamily.fromName(map['fontFamily'] as String?),
      answerRevealMode: AnswerRevealMode.fromName(
        map['answerRevealMode'] as String?,
      ),
    );
  }

  static String _stringOr(Object? value, String fallback) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }

  /// Settings are persisted one key at a time; this keeps nested lists safe.
  Map<String, dynamic> toFlatMap() => {
    for (final entry in toMap().entries)
      if (entry.value is List<int>)
        entry.key: (entry.value as List<int>).join(',')
      else
        entry.key: entry.value,
  };

  factory AppSettings.fromFlatMap(Map<dynamic, dynamic> map) {
    final merged = Map<String, dynamic>.from(map);
    for (final key in ['learningStepsMinutes', 'relearningStepsMinutes']) {
      final raw = merged[key];
      if (raw is String) {
        merged[key] = raw
            .split(',')
            .map((value) => int.tryParse(value.trim()))
            .whereType<int>()
            .toList();
      }
    }
    return AppSettings.fromMap(merged);
  }

  static int _clampInt(Object? value, int fallback, int min, int max) {
    final number = value is num ? value.toInt() : fallback;
    return number.clamp(min, max);
  }

  static double _clampDouble(
    Object? value,
    double fallback,
    double min,
    double max,
  ) {
    final number = value is num ? value.toDouble() : fallback;
    return number.clamp(min, max);
  }

  static List<int> _steps(Object? value, {required List<int> fallback}) {
    if (value is! List) return List<int>.from(fallback);
    final steps =
        value
            .whereType<num>()
            .map((step) => step.toInt())
            .where((step) => step >= 1 && step <= 1440)
            .toSet()
            .toList()
          ..sort();
    return steps.isEmpty ? [] : steps;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppSettings &&
        other.theme == theme &&
        other.newCardsPerDay == newCardsPerDay &&
        other.reviewsPerDay == reviewsPerDay &&
        other.desiredRetention == desiredRetention &&
        _sameSteps(other.learningStepsMinutes, learningStepsMinutes) &&
        _sameSteps(other.relearningStepsMinutes, relearningStepsMinutes) &&
        other.dailyGoal == dailyGoal &&
        other.remindersEnabled == remindersEnabled &&
        other.reminderHour == reminderHour &&
        other.reminderMinute == reminderMinute &&
        other.swipeToRate == swipeToRate &&
        other.animationsEnabled == animationsEnabled &&
        other.textScale == textScale &&
        other.keyboardShortcuts == keyboardShortcuts &&
        other.hapticFeedback == hapticFeedback &&
        other.aiProviderId == aiProviderId &&
        other.aiBaseUrl == aiBaseUrl &&
        other.aiModel == aiModel &&
        other.aiSourceLanguage == aiSourceLanguage &&
        other.aiOutputLanguage == aiOutputLanguage &&
        other.language == language &&
        other.accentColor == accentColor &&
        other.fontFamily == fontFamily &&
        other.answerRevealMode == answerRevealMode;
  }

  static bool _sameSteps(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
    theme,
    newCardsPerDay,
    reviewsPerDay,
    desiredRetention,
    Object.hashAll(learningStepsMinutes),
    Object.hashAll(relearningStepsMinutes),
    dailyGoal,
    remindersEnabled,
    reminderHour,
    reminderMinute,
    swipeToRate,
    animationsEnabled,
    textScale,
    keyboardShortcuts,
    hapticFeedback,
    aiProviderId,
    aiBaseUrl,
    aiModel,
    aiSourceLanguage,
    aiOutputLanguage,
    language,
    accentColor,
    fontFamily,
    answerRevealMode,
  ]);
}
