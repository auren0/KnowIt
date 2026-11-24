import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/study_mode.dart';

/// Lightweight, compile-safe localization for English and Russian.
///
/// All user-visible text lives in this file. English is the fallback and the
/// default application language. [current] lets non-widget services (stats,
/// notifications, validation) use the same active locale as the UI.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = [Locale('en'), Locale('ru')];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<Object>> localizationsDelegates = [
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static AppLocalizations _current = const AppLocalizations(Locale('en'));

  static AppLocalizations get current => _current;

  /// Allows startup code (notifications, diagnostics) to use the persisted
  /// language before the first MaterialApp frame.
  static void useLocale(Locale locale) {
    _current = AppLocalizations(
      Locale(locale.languageCode == 'ru' ? 'ru' : 'en'),
    );
  }

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ?? _current;

  bool get isRussian => locale.languageCode == 'ru';

  Locale get dateLocale => locale;

  String _t(String en, String ru) => isRussian ? ru : en;

  /// Locale switch for service-layer messages that are shown to users.
  String bi(String en, String ru) => _t(en, ru);

  String appTitle() => 'KnowIt';

  // ---------------------------------------------------------------------------
  // Navigation and common actions
  // ---------------------------------------------------------------------------
  String get collections => _t('Collections', 'Коллекции');
  String get browse => _t('Browse', 'Поиск');
  String get create => _t('Create', 'Создать');
  String get statistics => _t('Statistics', 'Статистика');
  String get settings => _t('Settings', 'Настройки');
  String get overview => _t('Overview', 'Обзор');
  String get cards => _t('Cards', 'Карточки');
  String get stats => _t('Stats', 'Статистика');
  String get study => _t('Study', 'Учить');
  String get cancel => _t('Cancel', 'Отмена');
  String get save => _t('Save', 'Сохранить');
  String get saveChanges => _t('Save changes', 'Сохранить изменения');
  String get delete => _t('Delete', 'Удалить');
  String get close => _t('Close', 'Закрыть');
  String get retry => _t('Retry', 'Повторить');
  String get tryAgain => _t('Try again', 'Попробовать снова');
  String get apply => _t('Apply', 'Применить');
  String get edit => _t('Edit', 'Изменить');
  String get duplicate => _t('Duplicate', 'Дублировать');
  String get move => _t('Move', 'Переместить');
  String get add => _t('Add', 'Добавить');
  String get clear => _t('Clear', 'Очистить');
  String get reset => _t('Reset', 'Сбросить');
  String get undo => _t('Undo', 'Отменить');
  String get done => _t('Done', 'Готово');
  String get import => _t('Import', 'Импорт');
  String get export => _t('Export', 'Экспорт');
  String get remove => _t('Remove', 'Удалить');
  String get selectAll => _t('Select all', 'Выбрать все');
  String get selectNone => _t('Select none', 'Снять выбор');
  String get clearAll => _t('Clear all', 'Очистить выбор');
  String get testConnection => _t('Test connection', 'Проверить подключение');
  String get configure => _t('Configure', 'Настроить');
  String get configureAi => _t('Configure AI', 'Настроить ИИ');
  String get configureProvider =>
      _t('Configure provider', 'Настроить провайдера');
  String get fromPath => _t('From path', 'Из файла');
  String get newBadge => _t('New', 'Новые');
  String get dueBadge => _t('Due', 'К повторению');
  String get practice => _t('Practice', 'Практика');
  String get noSchedule => _t('No schedule', 'Без расписания');
  String get optional => _t('optional', 'необязательно');
  String get more => _t('More', 'Больше');
  String get less => _t('Less', 'Меньше');
  String get again => _t('Again', 'Снова');
  String get hard => _t('Hard', 'Трудно');
  String get good => _t('Good', 'Хорошо');
  String get easy => _t('Easy', 'Легко');
  String ratingLabel(int rating) => switch (rating) {
    1 => again,
    2 => hard,
    3 => good,
    4 => easy,
    _ => unknown,
  };

  // ---------------------------------------------------------------------------
  // Plurals
  // ---------------------------------------------------------------------------
  String _ruPlural(int count, String one, String few, String many) {
    final n = count.abs();
    final mod10 = n % 10;
    final mod100 = n % 100;
    final word = (mod10 == 1 && mod100 != 11)
        ? one
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
        ? few
        : many;
    return '$count $word';
  }

  String cardCount(int count) => isRussian
      ? _ruPlural(count, 'карточка', 'карточки', 'карточек')
      : '$count ${count == 1 ? 'card' : 'cards'}';
  String noteCount(int count) => isRussian
      ? _ruPlural(count, 'заметка', 'заметки', 'заметок')
      : '$count ${count == 1 ? 'note' : 'notes'}';
  String reviewCount(int count) => isRussian
      ? _ruPlural(count, 'повторение', 'повторения', 'повторений')
      : '$count ${count == 1 ? 'review' : 'reviews'}';
  String collectionCount(int count) => isRussian
      ? _ruPlural(count, 'коллекция', 'коллекции', 'коллекций')
      : '$count ${count == 1 ? 'collection' : 'collections'}';
  String deckCount(int count) => isRussian
      ? _ruPlural(count, 'колода', 'колоды', 'колод')
      : '$count ${count == 1 ? 'deck' : 'decks'}';
  String subcollectionCount(int count) => isRussian
      ? _ruPlural(count, 'подколлекция', 'подколлекции', 'подколлекций')
      : '$count ${count == 1 ? 'subcollection' : 'subcollections'}';
  String characterCount(int count) => isRussian
      ? _ruPlural(count, 'символ', 'символа', 'символов')
      : '$count ${count == 1 ? 'character' : 'characters'}';
  String mediaCount(int count) => isRussian
      ? _ruPlural(count, 'медиафайл', 'медиафайла', 'медиафайлов')
      : '$count media ${count == 1 ? 'file' : 'files'}';
  String dayCount(int count) => isRussian
      ? _ruPlural(count, 'день', 'дня', 'дней')
      : '$count ${count == 1 ? 'day' : 'days'}';
  String reviewedTimes(int count) => isRussian
      ? _ruPlural(count, 'раз', 'раза', 'раз')
      : '$count ${count == 1 ? 'time' : 'times'}';
  String scheduledReviewCount(int count) => isRussian
      ? _ruPlural(
          count,
          'запланированное повторение',
          'запланированных повторения',
          'запланированных повторений',
        )
      : '$count scheduled ${count == 1 ? 'review' : 'reviews'}';

  // ---------------------------------------------------------------------------
  // Language, theme, accent and typography labels
  // ---------------------------------------------------------------------------
  String get language => _t('Language', 'Язык');
  String get languageHint => _t(
    'Interface language changes immediately.',
    'Язык интерфейса меняется сразу.',
  );
  String themeLabel(ThemePreference preference) => switch (preference) {
    ThemePreference.system => _t('System', 'Системная'),
    ThemePreference.light => _t('Light', 'Светлая'),
    ThemePreference.dark => _t('Dark', 'Тёмная'),
  };
  String get theme => _t('Theme', 'Тема');
  String get accentColor => _t('Accent colour', 'Акцентный цвет');
  String get accentColorHint => _t(
    'Applies to buttons, highlights and progress.',
    'Применяется к кнопкам, выделению и прогрессу.',
  );
  String accentLabel(AccentColor accent) => switch (accent) {
    AccentColor.yellow => _t('Yellow', 'Жёлтый'),
    AccentColor.blue => _t('Blue', 'Синий'),
    AccentColor.green => _t('Green', 'Зелёный'),
    AccentColor.purple => _t('Purple', 'Фиолетовый'),
    AccentColor.orange => _t('Orange', 'Оранжевый'),
    AccentColor.red => _t('Red', 'Красный'),
    AccentColor.pink => _t('Pink', 'Розовый'),
    AccentColor.cyan => _t('Cyan', 'Голубой'),
    AccentColor.teal => _t('Teal', 'Бирюзовый'),
    AccentColor.indigo => _t('Indigo', 'Индиго'),
    AccentColor.mint => _t('Mint', 'Мятный'),
    AccentColor.coral => _t('Coral', 'Коралловый'),
  };
  String get fontFamily => _t('Font', 'Шрифт');
  String get fontFamilyHint => _t(
    'Nunito is the default KnowIt typeface.',
    'Nunito — основной шрифт KnowIt.',
  );
  String fontLabel(AppFontFamily font) => switch (font) {
    AppFontFamily.nunito => 'Nunito',
    AppFontFamily.jetBrainsMono => 'JetBrains Mono',
  };

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------
  String get appearance => _t('Appearance', 'Внешний вид');
  String get appearanceSubtitle =>
      _t('Theme, language, colour and typography', 'Тема, язык, цвет и шрифт');
  String get textSize => _t('Text size', 'Размер текста');
  String get animations => _t('Animations', 'Анимации');
  String get cardFlipAnimation =>
      _t('Card flip animation', 'Анимация переворота карточки');
  String get swipeToRate => _t('Swipe to rate', 'Свайпы для оценки');
  String get swipeToRateSubtitle => _t(
    'Swipe left for Again, right for Good',
    'Свайп влево — «Снова», вправо — «Хорошо»',
  );
  String get hapticFeedback => _t('Haptic feedback', 'Тактильная отдача');
  String get hapticFeedbackSubtitle => _t(
    'Light touch feedback while studying',
    'Лёгкая вибрация во время учёбы',
  );
  String get keyboardShortcuts => _t('Keyboard shortcuts', 'Горячие клавиши');
  String get keyboardShortcutsSubtitle =>
      _t('Space, 1–4 and U while studying', 'Пробел, 1–4 и U во время учёбы');
  String get studySection => _t('Study', 'Учёба');
  String get studySectionSubtitle => _t(
    'FSRS uses these values to schedule your cards.',
    'FSRS использует эти значения для планирования карточек.',
  );
  String get newCardsPerDay => _t('New cards per day', 'Новых карточек в день');
  String get reviewsPerDay => _t('Reviews per day', 'Повторений в день');
  String get dailyGoal =>
      _t('Daily goal (reviews)', 'Цель на день (повторения)');
  String get desiredRetention => _t('Desired retention', 'Желаемое удержание');
  String get retentionHelp => _t(
    'Higher retention means more frequent reviews. 90% is a balanced default.',
    'Более высокое удержание означает более частые повторения. '
        '90% — сбалансированное значение по умолчанию.',
  );
  String get learningSteps => _t('Learning steps', 'Шаги обучения');
  String get relearningSteps => _t('Relearning steps', 'Шаги переобучения');
  String get minutesCommaSeparated =>
      _t('Minutes, separated by commas', 'Минуты через запятую');
  String get learningStepsHelp => _t(
    'A new card moves through these short steps before it graduates to days. '
        'Leave empty to graduate immediately.',
    'Новая карточка проходит эти короткие шаги, прежде чем перейти к дням. '
        'Оставьте пустым, чтобы сразу перейти к повторениям.',
  );
  String get relearningStepsHelp => _t(
    'A forgotten review card is rehearsed in these steps before returning to '
        'long intervals.',
    'Забытая карточка повторяется по этим шагам, прежде чем вернуться к '
        'длинным интервалам.',
  );
  String get stepsValidation => _t(
    'Use whole minutes between 1 and 1440.',
    'Используйте целые минуты от 1 до 1440.',
  );
  String get graduateImmediately =>
      _t('Graduate immediately', 'Сразу перейти к повторениям');
  String get returnToReviewImmediately =>
      _t('Return to review immediately', 'Сразу вернуться к повторениям');
  String minutesList(List<int> minutes) =>
      isRussian ? '${minutes.join(', ')} мин' : '${minutes.join(', ')} minutes';
  String get studyFootnote => _t(
    'Changing limits or steps never deletes scheduling data. Existing cards '
        'keep their due dates.',
    'Изменение лимитов или шагов не удаляет данные планирования. '
        'Существующие карточки сохраняют свои сроки.',
  );
  String get answerReveal => _t('Answer reveal', 'Показ ответа');
  String get answerRevealHint => _t(
    'Choose how the answer appears when you tap a card.',
    'Выберите, как ответ появляется при нажатии на карточку.',
  );
  String get flipAnimation => _t('Flip animation', 'Переворот');
  String get instantReveal => _t('Instant reveal', 'Мгновенно');
  String get flipAnimationDescription => _t(
    'The card rotates to reveal the answer. Smooth and animated.',
    'Карточка переворачивается, показывая ответ. Плавно и наглядно.',
  );
  String get instantRevealDescription => _t(
    'The answer appears immediately, without rotation — like Anki.',
    'Ответ появляется сразу, без переворота — как в Anki.',
  );
  String get reducedMotionNote => _t(
    'Animations are reduced automatically when your system requests it.',
    'Анимации автоматически сокращаются, если так настроена система.',
  );
  String get reminders => _t('Reminders', 'Напоминания');
  String get dailyStudyReminder =>
      _t('Daily study reminder', 'Ежедневное напоминание');
  String everyDayAt(String time) =>
      _t('Every day at $time', 'Каждый день в $time');
  String get remindersOff => _t(
    'Off — no notifications will be sent',
    'Выключено — уведомлений не будет',
  );
  String get reminderTime => _t('Reminder time', 'Время напоминания');
  String get remindersFootnote => _t(
    'Reminders are local to this device and optional. Notification permission '
        'is requested only when you enable them.',
    'Напоминания работают локально на этом устройстве и необязательны. '
        'Разрешение запрашивается только при включении.',
  );
  String get remindersPermissionFailed => _t(
    'Reminders could not be enabled. Check notification permissions in your '
        'system settings.',
    'Не удалось включить напоминания. Проверьте разрешения на уведомления '
        'в настройках системы.',
  );
  String get notificationsDenied => _t(
    'Notification permission was not granted. You can allow it in your system '
        'settings.',
    'Разрешение на уведомления не выдано. Его можно включить в настройках '
        'системы.',
  );
  String get data => _t('Data', 'Данные');
  String get dataSubtitle => _t(
    'Everything is stored locally and works offline.',
    'Всё хранится локально и работает без интернета.',
  );
  String get exportBackup => _t('Export backup', 'Экспорт резервной копии');
  String get exportBackupSubtitle => _t(
    'Copy JSON or save a backup file',
    'Скопировать JSON или сохранить файл резервной копии',
  );
  String get importBackup => _t('Import backup', 'Импорт резервной копии');
  String get importBackupSubtitle => _t(
    'Merge or replace from a KnowIt backup',
    'Объединить или заменить из резервной копии KnowIt',
  );
  String get importAnki =>
      _t('Import from Anki (.apkg)', 'Импорт из Anki (.apkg)');
  String get importAnkiSubtitle => _t(
    'Preview decks and cards before importing; scheduling starts fresh',
    'Просмотрите колоды и карточки перед импортом; планирование начнётся заново',
  );
  String get exportAnki =>
      _t('Export to Anki (.apkg)', 'Экспорт в Anki (.apkg)');
  String get exportAnkiSubtitle => _t(
    'Classic APKG · cards export as new, scheduling is not transferred',
    'Классический APKG · карточки экспортируются как новые, планирование '
        'не переносится',
  );
  String get backupFiles => _t('Backup files', 'Файлы резервных копий');
  String get backupFilesSubtitle => _t(
    'Restore or delete saved backups',
    'Восстановить или удалить сохранённые копии',
  );
  String librarySummary(int collections, int cards, int logs) => isRussian
      ? '$collections колл. · $cards карточек · $logs повторений'
      : '$collections collections · $cards cards · $logs reviews';
  String backupSummary(
    int collections,
    int cards,
    int logs,
    bool replaced,
  ) => isRussian
      ? '$collections колод, $cards карточек, $logs повторений — '
            '${replaced ? 'восстановлено' : 'объединено'}'
      : '$collections ${collections == 1 ? 'deck' : 'decks'}, '
            '$cards ${cards == 1 ? 'card' : 'cards'}, '
            '$logs ${logs == 1 ? 'review' : 'reviews'} '
            '${replaced ? 'restored' : 'merged'}';
  String ankiImportResultSummary(
    int notes,
    int cards,
    int skippedDuplicates,
  ) => isRussian
      ? 'импортировано заметок: $notes · карточек: $cards'
            '${skippedDuplicates > 0 ? ' · пропущено дубликатов: $skippedDuplicates' : ''}'
      : '$notes ${notes == 1 ? 'note' : 'notes'} · '
            '$cards ${cards == 1 ? 'card' : 'cards'} imported'
            '${skippedDuplicates > 0 ? ' · $skippedDuplicates duplicates skipped' : ''}';
  String ankiExportSummary(int notes, int cards, int media) => isRussian
      ? 'заметок: $notes · карточек: $cards · медиафайлов: $media'
      : '$notes ${notes == 1 ? 'note' : 'notes'} · '
            '$cards ${cards == 1 ? 'card' : 'cards'} · '
            '$media media ${media == 1 ? 'file' : 'files'}';
  String get dataFootnote => _t(
    'JSON backup/restore and classic Anki APKG import/export are supported. '
        'APKG scheduling is not transferred.',
    'Поддерживаются резервное копирование JSON и импорт/экспорт классических '
        'APKG Anki. Планирование APKG не переносится.',
  );
  String get cloudSync => _t('Cloud sync', 'Облачная синхронизация');
  String get noCloudBackend =>
      _t('No cloud backend configured', 'Облачный сервис не настроен');
  String syncFootnote(int tombstones) => _t(
    'Offline mode is fully functional. Local foundations are ready: stable '
        'IDs, modification timestamps, deletion tombstones and append-only '
        'review-history merging. $tombstones pending '
        '${tombstones == 1 ? 'tombstone' : 'tombstones'}.',
    'Автономный режим полностью работает. Локальная основа готова: стабильные '
        'ID, временные метки изменений, надгробия удалений и объединение '
        'истории повторений. Ожидает надгробий: $tombstones.',
  );
  String get syncFootnoteDetail => _t(
    'No provider credentials or transport are bundled, so no data is sent '
        'anywhere. A backend can be added later without changing the local '
        'database.',
    'Учётные данные и транспорт не встроены, поэтому данные никуда не '
        'отправляются. Сервер можно добавить позже без изменения локальной базы.',
  );
  String get aiFeatures => _t('AI features', 'Возможности ИИ');
  String get noAiProvider =>
      _t('No AI provider configured', 'Провайдер ИИ не настроен');
  String get aiConfiguredSubtitle => _t(
    'OpenAI-compatible endpoint · API key stored securely',
    'Совместимый с OpenAI endpoint · ключ API хранится безопасно',
  );
  String get aiNotConfiguredSubtitle => _t(
    'KnowIt is fully usable without AI. Connect your own OpenAI-compatible '
        'provider to generate cards.',
    'KnowIt полностью работает без ИИ. Подключите собственный провайдер, '
        'совместимый с OpenAI, чтобы генерировать карточки.',
  );
  String get secureStorageUnavailable => _t(
    'Secure credential storage is unavailable on this platform, so AI keys '
        'cannot be stored safely.',
    'На этой платформе недоступно безопасное хранилище, поэтому ключи ИИ '
        'нельзя сохранить надёжно.',
  );
  String get generateWithAi =>
      _t('Generate flashcards with AI', 'Генерировать карточки с ИИ');
  String get generateWithAiSubtitle => _t(
    'Generate, review and edit cards before saving them to a deck.',
    'Создавайте, проверяйте и редактируйте карточки перед сохранением в колоду.',
  );
  String get aiKeyFootnote => _t(
    'Client-side API keys can be extracted from a device. For shared or '
        'commercial use, connect through an authenticated backend proxy with '
        'usage limits. Keys are never included in backups.',
    'Ключи API на клиенте можно извлечь с устройства. Для общего или '
        'коммерческого использования подключайтесь через прокси с '
        'аутентификацией и лимитами. Ключи не попадают в резервные копии.',
  );
  String get about => _t('About', 'О приложении');
  String version(String version) => _t('Version $version', 'Версия $version');
  String get spacedRepetition =>
      _t('Spaced repetition', 'Интервальное повторение');
  String get spacedRepetitionSubtitle => _t(
    'FSRS (Free Spaced Repetition Scheduler) via the official Dart '
        'implementation. Scheduling runs locally and independently of the UI.',
    'FSRS (Free Spaced Repetition Scheduler) через официальную реализацию '
        'на Dart. Планирование работает локально и независимо от интерфейса.',
  );
  String get offlineFirst => _t('Offline first', 'Сначала офлайн');
  String get offlineFirstSubtitle => _t(
    'Decks, cards, schedules and review history are stored on this device with '
        'Hive. No account is required.',
    'Колоды, карточки, расписание и история повторений хранятся на этом '
        'устройстве в Hive. Аккаунт не нужен.',
  );
  String get aboutFootnote => _t(
    'Classic Anki APKG import/export is supported. Scheduling and review '
        'history are not transferred in either direction. Newer '
        'zstd-compressed Anki collections are rejected with an explanation.',
    'Поддерживается импорт/экспорт классических APKG Anki. Планирование и '
        'история повторений не переносятся в обе стороны. Новые коллекции Anki '
        'со сжатием zstd отклоняются с пояснением.',
  );

  // ---------------------------------------------------------------------------
  // Collections
  // ---------------------------------------------------------------------------
  String get newCollection => _t('New collection', 'Новая коллекция');
  String get newCollectionTitle => _t('New Collection', 'Новая коллекция');
  String get editCollectionTitle => _t('Edit Collection', 'Изменить коллекцию');
  String get createCollection => _t('Create Collection', 'Создать коллекцию');
  String get searchCollections => _t('Search collections', 'Поиск коллекций');
  String get clearSearch => _t('Clear search', 'Очистить поиск');
  String get sortCollections => _t('Sort collections', 'Сортировка коллекций');
  String get filterCollections => _t('Filter collections', 'Фильтр коллекций');
  String get studyAllDue => _t('Study all due cards', 'Учить все к повторению');
  String get noCollectionsTitle =>
      _t('No collections yet', 'Коллекций пока нет');
  String get noCollectionsMessage => _t(
    'Create your first collection and start building your knowledge one card '
        'at a time.',
    'Создайте первую коллекцию и начните собирать знания по одной карточке.',
  );
  String shownOfTotal(int shown, int total) => isRussian
      ? '$shown из $total коллекций'
      : '$shown of $total ${total == 1 ? 'collection' : 'collections'}';
  String dayStreakShort(int days) =>
      isRussian ? 'Серия: $days дн.' : '$days-day streak';
  String get dayStreak => _t('Day streak', 'Серия дней');
  String get noMatchingCollections =>
      _t('No matching collections', 'Нет подходящих коллекций');
  String get noMatchingCollectionsMessage => _t(
    'Try a different search term or clear the filter.',
    'Попробуйте другой запрос или сбросьте фильтр.',
  );
  String get resetSearchAndFilters =>
      _t('Reset search and filters', 'Сбросить поиск и фильтры');
  String collectionHasNoCards(String name) =>
      _t('$name has no cards yet.', 'В коллекции «$name» пока нет карточек.');
  String get addCardsFirst => _t(
    'Add cards to a collection first.',
    'Сначала добавьте карточки в коллекцию.',
  );
  String get allCollections => _t('All collections', 'Все коллекции');
  String get couldNotDuplicate => _t(
    'Could not duplicate this collection.',
    'Не удалось дублировать коллекцию.',
  );
  String duplicated(String name) =>
      _t('Duplicated $name', 'Коллекция «$name» дублирована');
  String deleteCollectionTitle(String name) =>
      _t('Delete $name?', 'Удалить «$name»?');
  String deleteCollectionBody(String cardPart, String subdeckPart) => _t(
    '$cardPart$subdeckPart will be deleted, together with their review '
        'history. You can undo this action right after deleting.',
    '$cardPart$subdeckPart будут удалены вместе с историей повторений. '
        'Действие можно отменить сразу после удаления.',
  );
  String cardPart(int count) => isRussian ? cardCount(count) : cardCount(count);
  String subdeckPart(int count) => count == 0
      ? ''
      : isRussian
      ? ' и ${subcollectionCount(count)}'
      : ' and ${subcollectionCount(count)}';
  String get andWord => _t('and', 'и');
  String deleted(String name) => _t('Deleted $name', '«$name» удалено');

  String get manualOrder => _t('Manual order', 'Вручную');
  String get nameAZ => _t('Name A → Z', 'По имени А → Я');
  String get newestFirst => _t('Newest first', 'Сначала новые');
  String get mostDue => _t('Most due', 'Больше к повторению');
  String get mostCards => _t('Most cards', 'Больше карточек');
  String get allCollectionsFilter => _t('All collections', 'Все коллекции');
  String get withCardsDue => _t('With cards due', 'Есть к повторению');
  String get withNewCards => _t('With new cards', 'Есть новые');
  String get emptyCollections => _t('Empty collections', 'Пустые коллекции');

  String get deckOptions => _t('Deck options', 'Параметры колоды');
  String get editDeck => _t('Edit deck', 'Изменить колоду');
  String get addSubdeck => _t('Add subdeck', 'Добавить подколоду');
  String get addSubcollection =>
      _t('Add subcollection', 'Добавить подколлекцию');
  String get nextReview => _t('Next', 'Далее');
  String nextReviewIn(String interval) => _t(
    ', next review in $interval',
    ', следующее повторение через $interval',
  );
  String get noCardsYet => _t('No cards yet', 'Карточек пока нет');
  String get allCaughtUp => _t('All caught up', 'Всё повторено');
  String dueCards(int count) =>
      isRussian ? '$count к повторению' : '$count due';
  String newCards(int count) => isRussian ? '$count новых' : '$count new';
  String nextDueLabel(String relative) =>
      _t('Next $relative', 'Далее $relative');

  String get collectionName => _t('Collection name', 'Название коллекции');
  String get collectionNameHint =>
      _t('e.g. Biology, English B2', 'например, Биология, Английский B2');
  String get collectionEmoji => _t('Collection emoji', 'Эмодзи коллекции');
  String get enterEmoji => _t('Enter an emoji', 'Введите эмодзи');
  String get descriptionOptional =>
      _t('Description (optional)', 'Описание (необязательно)');
  String get descriptionHint =>
      _t('What is this collection about?', 'О чём эта коллекция?');
  String get parentCollection => _t(
    'Parent collection (optional)',
    'Родительская коллекция (необязательно)',
  );
  String get noneTopLevel => _t('None — top level', 'Нет — верхний уровень');
  String get subcollectionsHelp => _t(
    'Subcollections are shown nested under their parent and are included when '
        'you study the parent.',
    'Подколлекции отображаются внутри родительской и включаются при её изучении.',
  );
  String get livePreview => _t('LIVE PREVIEW', 'ПРЕДПРОСМОТР');
  String get progressAutomatic => _t(
    'Progress and card counts update automatically as you study.',
    'Прогресс и количество карточек обновляются автоматически во время учёбы.',
  );
  String get pleaseEnterCollectionName =>
      _t('Please enter a collection name', 'Введите название коллекции');
  String get nameTooLong => _t(
    'Name is too long (max 60 characters)',
    'Название слишком длинное (максимум 60 символов)',
  );
  String get parentCycle => _t(
    'A deck cannot be placed inside its own subdeck.',
    'Колоду нельзя поместить внутрь её собственной подколоды.',
  );
  String get parentMissing => _t(
    'The parent deck no longer exists.',
    'Родительская колода больше не существует.',
  );
  String couldNotSaveCollection(Object error) => _t(
    'Could not save the collection. $error',
    'Не удалось сохранить коллекцию. $error',
  );
  String get discardChanges => _t('Discard changes?', 'Отменить изменения?');
  String get discardCollectionBody => _t(
    'Your changes to this collection are not saved.',
    'Изменения этой коллекции не сохранены.',
  );
  String get keepEditing => _t('Keep editing', 'Продолжить редактирование');
  String get discard => _t('Discard', 'Отменить');

  // ---------------------------------------------------------------------------
  // Browse / search
  // ---------------------------------------------------------------------------
  String studyResults(int count) =>
      isRussian ? 'Учить: $count' : 'Study $count';
  String get searchCardsDecksTags =>
      _t('Search cards, decks or tags', 'Поиск карточек, колод или тегов');
  String get collectionLabel => _t('Collection', 'Коллекция');
  String get tags => _t('Tags:', 'Теги:');
  String get all => _t('All', 'Все');
  String get newOnly => _t('New', 'Новые');
  String get learning => _t('Learning', 'Изучаются');
  String get inReview => _t('Review', 'Повторение');
  String get dueNow => _t('Due now', 'Сейчас к повторению');
  String get dueNowFilter => _t('Due now', 'К повторению');
  String relativeMinutes(int minutes) =>
      _t('in ${minutes}m', 'через $minutes мин');
  String relativeHours(int hours) => _t('in ${hours}h', 'через $hours ч');
  String relativeDays(int days) => _t('in ${days}d', 'через $days дн');
  String get nowWord => _t('now', 'сейчас');
  String get dueToday => _t('Due today', 'На сегодня');
  String get dueThisWeek => _t('Due this week', 'На этой неделе');
  String get overdue => _t('Overdue', 'Просрочено');
  String get findAnythingTitle =>
      _t('Find anything, instantly', 'Найдите что угодно мгновенно');
  String get findAnythingMessage => _t(
    'Search card text, collection names, tags and learning state.\n\n'
        'Try #biology, is:due, due:today, due:week or due:overdue.',
    'Ищите по тексту карточек, названиям коллекций, тегам и состоянию.\n\n'
        'Попробуйте #биология, is:due, due:today, due:week или due:overdue.',
  );
  String get noMatchingCards =>
      _t('No matching cards', 'Нет подходящих карточек');
  String get noMatchingCardsMessage => _t(
    'Try another term, clear a filter, or search across all collections.',
    'Попробуйте другой запрос, сбросьте фильтр или ищите по всем коллекциям.',
  );
  String get resetSearch => _t('Reset search', 'Сбросить поиск');
  String get unknownCollection =>
      _t('Unknown collection', 'Неизвестная коллекция');
  String get searchResults => _t('Search results', 'Результаты поиска');

  String get cardPreview => _t('Card preview', 'Предпросмотр карточки');
  String get front => _t('FRONT', 'ЛИЦЕВАЯ СТОРОНА');
  String get back => _t('BACK', 'ОБРАТНАЯ СТОРОНА');
  String get quickPractice => _t('Quick practice', 'Быстрая практика');
  String get notStudied => _t('Not studied', 'Не изучено');
  String get unscheduled => _t('Unscheduled', 'Без расписания');
  String get reversedVariant => _t('Reverse', 'Обратная');
  String clozeVariant(int index) =>
      isRussian ? 'Пропуск $index' : 'Cloze $index';
  String lapsesLabel(int count) =>
      isRussian ? 'пропусков: $count' : 'lapses $count';
  String stabilityLabel(String value) =>
      isRussian ? 'стабильность $value' : 'stability $value';
  String get cardDeleted => _t('Card deleted', 'Карточка удалена');
  String cardsDeleted(int count) =>
      isRussian ? 'Удалено карточек: $count' : '$count cards deleted';
  String get noteDuplicated => _t('Note duplicated', 'Заметка дублирована');
  String cardsDuplicated(int count) =>
      isRussian ? 'Дублировано карточек: $count' : '$count cards duplicated';
  String get createAnotherCollection => _t(
    'Create another collection to move cards into.',
    'Создайте другую коллекцию, чтобы переместить туда карточки.',
  );
  String moveCardTo(String count) => isRussian
      ? (count.isEmpty
            ? 'Переместить карточку'
            : 'Переместить карточку: $count')
      : 'Move card to';
  String moveCardsTo(int count) =>
      isRussian ? 'Переместить карточек: $count' : 'Move $count cards to';
  String movedTo(String name) => _t('Moved to $name', 'Перемещено в «$name»');
  String get cardSaved => _t('Card saved', 'Карточка сохранена');
  String get cardCreated => _t('Card created', 'Карточка создана');
  String get exitSelection => _t('Exit selection', 'Выйти из выбора');
  String selectedCount(int count) =>
      isRussian ? 'Выбрано: $count' : '$count selected';
  String get searchCardsAndTags =>
      _t('Search cards and tags', 'Поиск карточек и тегов');
  String get sortCards => _t('Sort cards', 'Сортировка карточек');
  String get filterCards => _t('Filter cards', 'Фильтр карточек');
  String get oldestFirst => _t('Oldest first', 'Сначала старые');
  String get alphabetical => _t('Alphabetical', 'По алфавиту');
  String get dueDate => _t('Due date', 'Дата повторения');
  String get learningState => _t('Learning state', 'Состояние изучения');
  String get allCards => _t('All cards', 'Все карточки');
  String get inReviewFilter => _t('In review', 'В повторении');
  String get withMedia => _t('With media', 'С медиа');
  String get clearFilters => _t('Clear filters', 'Сбросить фильтры');
  String get addCard => _t('Add card', 'Добавить карточку');
  String get noCardsMessage => _t(
    'Add your first card and start building your knowledge.',
    'Добавьте первую карточку и начните собирать знания.',
  );
  String get tryDifferentSearch => _t(
    'Try a different search, sort or filter.',
    'Попробуйте другой поиск, сортировку или фильтр.',
  );
  String summaryLine(int visible, int total) => isRussian
      ? '$visible из $total карточек'
      : '$visible of $total ${total == 1 ? 'card' : 'cards'}';
  String get deleteCardsTitle => _t('Delete cards?', 'Удалить карточки?');
  String deleteCardsTitleCount(int count) =>
      isRussian ? 'Удалить карточки ($count)?' : 'Delete $count cards?';
  String get deleteCardsBody => _t(
    'Review history is kept, and this action can be undone right afterwards.',
    'История повторений сохранится, действие можно сразу отменить.',
  );
  String get cardOptions => _t('Card options', 'Параметры карточки');
  String get deleteCard => _t('Delete card', 'Удалить карточку');
  String get newCardTitle => _t('New card', 'Новая карточка');
  String get editCardTitle => _t('Edit card', 'Изменить карточку');
  String get createCard => _t('Create card', 'Создать карточку');
  String get cardType => _t('CARD TYPE', 'ТИП КАРТОЧКИ');
  String get deck => _t('Deck', 'Колода');
  String get frontLabel => _t('Front', 'Лицевая сторона');
  String get backLabel => _t('Back', 'Обратная сторона');
  String get clozeText => _t('Text with cloze deletions', 'Текст с пропусками');
  String get extraExplanation => _t(
    'Extra explanation (optional)',
    'Дополнительное пояснение (необязательно)',
  );
  String get frontHint => _t(
    'Write a question, term or prompt',
    'Напишите вопрос, термин или подсказку',
  );
  String get questionOrTerm => _t('Question or term…', 'Вопрос или термин…');
  String get answerHint =>
      _t('Write the answer or definition', 'Напишите ответ или определение');
  String get answerEllipsis => _t('Answer…', 'Ответ…');
  String get optionalNotes => _t(
    'Optional notes shown after revealing…',
    'Необязательные заметки после ответа…',
  );
  String get clozeHint => _t(
    'Use {{c1::answer}} to hide text. Add {{c2::another}} for multiple '
        'deletions.',
    'Используйте {{c1::ответ}}, чтобы скрыть текст. Добавьте {{c2::другой}} '
        'для нескольких пропусков.',
  );
  String get pressEnterToAddTag =>
      _t('Press enter to add a tag', 'Нажмите Enter, чтобы добавить тег');
  String get bold => _t('Bold', 'Жирный');
  String get italic => _t('Italic', 'Курсив');
  String get underline => _t('Underline', 'Подчёркнутый');
  String get highlight => _t('Highlight', 'Выделение');
  String get code => _t('Code', 'Код');
  String get cloze => _t('Cloze', 'Пропуск');
  String get tagHint => _t('e.g. biology', 'например, биология');
  String get tagsCommaSeparated =>
      _t('Tags (comma separated)', 'Теги (через запятую)');
  String get attachments => _t('Attachments', 'Вложения');
  String get imageFileMissing =>
      _t('Image file is missing', 'Файл изображения отсутствует');
  String get imageLoadFailed =>
      _t('Image could not be loaded', 'Не удалось загрузить изображение');
  String get loading => _t('Loading…', 'Загрузка…');
  String get audioFileMissing =>
      _t('Audio file is missing', 'Аудиофайл отсутствует');
  String get audioUnsupportedFormat =>
      _t('Unsupported audio format', 'Неподдерживаемый формат аудио');
  String get audioFileCorrupted =>
      _t('Audio file is corrupted', 'Аудиофайл повреждён');
  String get audioPlaybackFailed =>
      _t('Audio playback failed', 'Ошибка воспроизведения аудио');
  String get audioPlaying => _t('Playing…', 'Воспроизведение…');
  String get attachmentsHint => _t(
    'Images and audio are copied into KnowIt',
    'Изображения и аудио копируются в KnowIt',
  );
  String get addImage => _t('Add image', 'Добавить изображение');
  String get addAudio => _t('Add audio', 'Добавить аудио');
  String get removeAttachment => _t('Remove attachment', 'Удалить вложение');
  String get attachImageFromPath =>
      _t('Attach image from path', 'Прикрепить изображение по пути');
  String get attachAudioFromPath =>
      _t('Attach audio from path', 'Прикрепить аудио по пути');
  String get filePath => _t('File path', 'Путь к файлу');
  String get attach => _t('Attach', 'Прикрепить');
  String get chooseDeckForCard =>
      _t('Choose a deck for this card.', 'Выберите колоду для этой карточки.');
  String couldNotSaveCard(Object error) => _t(
    'Could not save the card. $error',
    'Не удалось сохранить карточку. $error',
  );
  String get deleteNoteTitle => _t('Delete this note?', 'Удалить эту заметку?');
  String get deleteNoteBody => _t(
    'Every card generated from this note and its review history will be '
        'removed. You can undo this from the card list right after deleting.',
    'Все карточки этой заметки и их история повторений будут удалены. '
        'Это можно отменить в списке карточек сразу после удаления.',
  );
  String get readOnlyNoteBody => _t(
    'This card and its review history will be removed. You can undo this from '
        'the card list right after deleting.',
    'Карточка и её история повторений будут удалены. Это можно отменить '
        'в списке карточек сразу после удаления.',
  );
  String get formattingHint => _t(
    'Formatting: **bold**, *italic*, __underline__, ==highlight==, `code`. '
        'Markup is rendered while studying.',
    'Форматирование: **жирный**, *курсив*, __подчёркнутый__, ==выделение==, '
        '`код`. Разметка отображается во время учёбы.',
  );
  String get cardPreviewEmpty => _t(
    'Your card preview will appear here.',
    'Здесь появится предпросмотр карточки.',
  );
  String get noteWillCreate => _t(
    'This note will create independently scheduled cards. Each direction or '
        'cloze deletion keeps its own review history.',
    'Эта заметка создаст независимо запланированные карточки. Каждое '
        'направление или пропуск сохраняет свою историю повторений.',
  );
  String noteWillCreateCount(int count) => isRussian
      ? 'Эта заметка создаст ${cardCount(count)} с независимым расписанием. '
            'Каждое направление или пропуск сохраняет свою историю повторений.'
      : 'This note will create $count independently scheduled '
            '${count == 1 ? 'card' : 'cards'}. Each direction or cloze '
            'deletion keeps its own review history.';
  String cardTypeLabelOf(CardType type) => cardTypeLabel(type.index);
  String cardTypeDescriptionOf(CardType type) =>
      cardTypeDescription(type.index);
  String learningStateLabelOf(CardLearningState state) =>
      learningStateLabel(state.index);

  // ---------------------------------------------------------------------------
  // Statistics
  // ---------------------------------------------------------------------------
  String statisticsFor(String name) =>
      _t('Statistics for $name', 'Статистика для «$name»');
  String get realDataNotice => _t(
    'Your real study data will appear here after your first review. Nothing is '
        'simulated.',
    'Реальные данные появятся здесь после первого повторения. Ничего '
        'не имитируется.',
  );
  String get reviewsToday => _t('Reviews today', 'Повторений сегодня');
  String get retention => _t('Retention', 'Удержание');
  String get totalCards => _t('Total cards', 'Всего карточек');
  String get cardsStudied => _t('Cards studied', 'Изучено карточек');
  String get studyTime => _t('Study time', 'Время учёбы');
  String get today => _t('Today', 'Сегодня');
  String stillDue(int count) =>
      isRussian ? '$count ещё к повторению' : '$count still due';
  String get noCardsWaiting => _t(
    'No cards waiting. Enjoy the calm.',
    'Нет карточек к повторению. Отдыхайте.',
  );
  String reviewedRemaining(int reviewed, int remaining) => isRussian
      ? 'Сегодня повторено: $reviewed · осталось: $remaining'
      : '$reviewed reviewed today · $remaining remaining';
  String get reviewHeatmap => _t('Review heatmap', 'Карта повторений');
  String activeDaysLongest(int days, int longest) => isRussian
      ? 'Активных дней: $days · лучшая серия: $longest'
      : '$days active days · longest streak $longest';
  String get last30Days => _t('Last 30 days', 'Последние 30 дней');
  String get reviewsPerDayChart => _t(
    'Reviews per day, with new cards highlighted',
    'Повторений в день, новые карточки выделены',
  );
  String get howYouRate => _t('How you rate', 'Ваши оценки');
  String acrossReviews(int count) =>
      isRussian ? 'По ${reviewCount(count)}' : 'Across ${reviewCount(count)}';
  String get estimatedRetention =>
      _t('Estimated retention', 'Оценка удержания');
  String basedOnScheduled(int count) => isRussian
      ? 'На основе: ${scheduledReviewCount(count)}'
      : 'Based on ${scheduledReviewCount(count)}';
  String get dueWorkloadByCollection =>
      _t('Due workload by collection', 'Нагрузка по коллекциям');
  String get difficultCards => _t('Difficult cards', 'Сложные карточки');
  String get cardsForgetMost =>
      _t('Cards you forget most often', 'Карточки, которые вы чаще забываете');
  String get noCardsToAnalyse =>
      _t('No cards to analyse yet.', 'Пока нет карточек для анализа.');
  String get noDifficultCards => _t(
    'No repeatedly forgotten cards. Nice.',
    'Нет часто забываемых карточек. Отлично.',
  );
  String get practiceDifficultCards =>
      _t('Practice difficult cards', 'Практика сложных карточек');
  String get recentReviews => _t('Recent reviews', 'Недавние повторения');
  String get latestActivity =>
      _t('Your latest study activity', 'Ваша последняя активность');
  String get noCardsStatsTitle => _t('No cards yet', 'Карточек пока нет');
  String get noCardsStatsMessage => _t(
    'Create a collection and add cards to start building your learning '
        'statistics.',
    'Создайте коллекцию и добавьте карточки, чтобы начать собирать статистику.',
  );
  String get allScheduledDone => _t(
    'All scheduled reviews done',
    'Все запланированные повторения выполнены',
  );
  String allScheduledDoneMessage(int total) => _t(
    'You have $total cards in this collection. Come back when the next review '
        'is due, or try cram mode.',
    'В этой коллекции $total карточек. Вернитесь, когда подойдёт следующее '
        'повторение, или попробуйте режим зубрёжки.',
  );
  String get difficultCardClickHint =>
      _t('Cards you forget most often', 'Карточки, которые вы чаще забываете');
  String get noCollectionsStats =>
      _t('No collections yet.', 'Коллекций пока нет.');
  String get deletedCard => _t('Deleted card', 'Удалённая карточка');
  String get previousYear => _t('Previous year', 'Предыдущий год');
  String get nextYear => _t('Next year', 'Следующий год');
  String yearActivity(int year) => _t('$year activity', 'Активность за $year');
  String activityForYear(int year, int reviews, int activeDays) => isRussian
      ? '$year · повторений: $reviews · активных дней: $activeDays'
      : '$year · $reviews reviews · $activeDays active days';
  String get noActivityThisYear =>
      _t('No activity this year', 'В этом году активности нет');

  // ---------------------------------------------------------------------------
  // Study
  // ---------------------------------------------------------------------------
  String get showAnswer => _t('Show answer', 'Показать ответ');
  String get answer => _t('ANSWER', 'ОТВЕТ');
  String get tapToReveal =>
      _t('Tap to reveal the answer', 'Нажмите, чтобы показать ответ');
  String get sessionComplete => _t('Session complete', 'Сессия завершена');
  String get allCaughtUpTitle => _t('All caught up', 'Всё повторено');
  String get nothingDueQueue =>
      _t('Nothing was due in this queue.', 'В этой очереди нечего повторять.');
  String get outstandingRecall => _t(
    'Outstanding recall. Your schedule is up to date.',
    'Отличное запоминание. Расписание обновлено.',
  );
  String get solidSession => _t(
    'Solid session. Keep the rhythm going.',
    'Хорошая сессия. Продолжайте в том же ритме.',
  );
  String get everyReviewCounts => _t(
    'Every review counts. Difficult cards are doing their job.',
    'Каждое повторение важно. Сложные карточки делают свою работу.',
  );
  String get reviewsStat => _t('Reviews', 'Повторения');
  String get recallStat => _t('Recall', 'Запоминание');
  String get dailyLimitsNote => _t(
    'Daily limits are doing their job. Some cards were held back. You can '
        'raise the limits in Settings.',
    'Дневные лимиты работают. Некоторые карточки были отложены. Лимиты можно '
        'увеличить в настройках.',
  );
  String get studyAgain => _t('Study again', 'Учить снова');
  String get undoLastRating =>
      _t('Undo last rating', 'Отменить последнюю оценку');
  String get endSession => _t('End session', 'Завершить сессию');
  String get keepStudying => _t('Keep studying', 'Продолжить учёбу');
  String get endSessionTitle => _t('End this session?', 'Завершить сессию?');
  String completedReviews(int count) => isRussian
      ? 'Вы выполнили ${reviewCount(count)}. Прогресс уже сохранён.'
      : 'You completed ${reviewCount(count)}. Your progress is already saved.';
  String couldNotSaveReview(Object error) => _t(
    'Could not save this review. $error',
    'Не удалось сохранить повторение. $error',
  );
  String couldNotUndo(Object error) =>
      _t('Could not undo. $error', 'Не удалось отменить. $error');
  String get sessionCouldNotStart =>
      _t('Session could not start', 'Не удалось начать сессию');
  String get couldNotPrepareSession => _t(
    'Could not prepare this study session.',
    'Не удалось подготовить сессию.',
  );
  String get keyboardHint => _t(
    'Space to reveal · 1–4 to rate · U to undo',
    'Пробел — показать · 1–4 — оценить · U — отменить',
  );
  String get undoRatingTooltip =>
      _t('Undo last rating (U)', 'Отменить последнюю оценку (U)');
  String get endSessionTooltip => _t('End session', 'Завершить сессию');
  String get practiceNoScheduleNote => _t(
    'Practice mode: your spaced-repetition schedule will not be changed.',
    'Режим практики: расписание интервального повторения не изменится.',
  );
  String dueLabel(String relative) =>
      isRussian ? 'К повторению $relative' : 'Due $relative';
  String reviewedTimesShort(int count) => isRussian
      ? 'Повторено: ${reviewedTimes(count)}'
      : 'Reviewed ${reviewedTimes(count)}';
  String get studyModes => _t('Study modes', 'Режимы учёбы');
  String studyDeck(String name) => _t('Study $name', 'Учить «$name»');
  String get onlySrsChanges => _t(
    'Only spaced repetition changes your schedule.',
    'Только интервальное повторение меняет расписание.',
  );
  String studyModeLabel(StudyMode mode) => switch (mode) {
    StudyMode.srs => _t('Spaced repetition', 'Интервальное повторение'),
    StudyMode.quick => _t('Quick review', 'Быстрое повторение'),
    StudyMode.cram => _t('Cram', 'Зубрёжка'),
    StudyMode.random => _t('Random practice', 'Случайная практика'),
    StudyMode.difficult => _t('Difficult cards', 'Сложные карточки'),
  };
  String studyModeShortLabel(StudyMode mode) => switch (mode) {
    StudyMode.srs => _t('Review', 'Повторение'),
    StudyMode.quick => _t('Quick', 'Быстро'),
    StudyMode.cram => _t('Cram', 'Зубрёжка'),
    StudyMode.random => _t('Random', 'Случайно'),
    StudyMode.difficult => _t('Difficult', 'Сложные'),
  };
  String studyModeDescription(StudyMode mode) => switch (mode) {
    StudyMode.srs => _t(
      'Smart scheduling based on when you are about to forget.',
      'Умное планирование с учётом того, когда вы можете забыть.',
    ),
    StudyMode.quick => _t(
      'Run through cards that are due, without changing the schedule.',
      'Пройдите карточки к повторению, не меняя расписание.',
    ),
    StudyMode.cram => _t(
      'Study a deck intensively. The schedule stays untouched.',
      'Интенсивно изучите колоду. Расписание не меняется.',
    ),
    StudyMode.random => _t(
      'Shuffle every card in the deck and practice freely.',
      'Перемешайте все карточки колоды и практикуйтесь свободно.',
    ),
    StudyMode.difficult => _t(
      'Focus on cards you keep forgetting.',
      'Сосредоточьтесь на карточках, которые постоянно забываете.',
    ),
  };

  // ---------------------------------------------------------------------------
  // Overview
  // ---------------------------------------------------------------------------
  String get firstCardPrompt => _t(
    'Add your first card to begin.',
    'Добавьте первую карточку, чтобы начать.',
  );
  String get nothingScheduledCaughtUp => _t(
    'Nothing scheduled — you are caught up.',
    'Ничего не запланировано — всё повторено.',
  );
  String nextReviewLower(String relative) =>
      _t('Next review $relative', 'Следующее повторение $relative');
  String get addCardsToStartStudying => _t(
    'Add cards to start studying',
    'Добавьте карточки, чтобы начать учить',
  );
  String studyNowReady(int count) =>
      _t('Study now · $count ready', 'Учить сейчас · готово: $count');
  String get studyNow => _t('Study now', 'Учить сейчас');
  String get moreModes => _t('More modes', 'Другие режимы');
  String get studyTip => _t(
    'Tip: keep cards short and focused. One idea per card is easier to '
        'remember.',
    'Совет: делайте карточки короткими. Одну идею на карточку запомнить проще.',
  );
  String get subcollections => _t('Subcollections', 'Подколлекции');
  String get subcollectionsEmptyHint => _t(
    'Organise related topics into subcollections.',
    'Объединяйте связанные темы в подколлекции.',
  );
  String includedWhenStudying(String name) =>
      _t('Included when studying $name.', 'Включаются при изучении «$name».');
  String get noSubcollections =>
      _t('No subcollections yet.', 'Подколлекций пока нет.');
  String get cardsSectionSubtitle => _t(
    'Open the Cards tab below to edit, search or move cards.',
    'Откройте вкладку «Карточки», чтобы редактировать, искать или перемещать.',
  );
  String get latestCards => _t('Latest cards', 'Последние карточки');
  String get collectionNotFound =>
      _t('Collection not found', 'Коллекция не найдена');
  String get collectionDeleted => _t(
    'This collection may have been deleted.',
    'Возможно, коллекция была удалена.',
  );
  String get goBack => _t('Go back', 'Назад');
  String studyCollectionTooltip(String name) =>
      _t('Study this collection', 'Учить эту коллекцию');
  String get collectionOptions =>
      _t('Collection options', 'Параметры коллекции');
  String get editCollection => _t('Edit collection', 'Изменить коллекцию');
  String get deckNotFound => _t('Deck not found', 'Колода не найдена');

  // ---------------------------------------------------------------------------
  // AI generation
  // ---------------------------------------------------------------------------
  String get aiFlashcards => _t('AI flashcards', 'Карточки с ИИ');
  String get aiProviderSettings =>
      _t('AI provider settings', 'Настройки провайдера ИИ');
  String get noAiProviderTitle =>
      _t('No AI provider is configured', 'Провайдер ИИ не настроен');
  String get noAiProviderBody => _t(
    'KnowIt works fully without AI. Add an OpenAI-compatible endpoint and '
        'your own API key to enable generation; the key is kept in secure '
        'storage, not in backups.',
    'KnowIt полностью работает без ИИ. Добавьте совместимый с OpenAI endpoint '
        'и собственный ключ API, чтобы включить генерацию; ключ хранится '
        'в защищённом хранилище, а не в резервных копиях.',
  );
  String usingProvider(String provider) => _t(
    'Using $provider. Your selected source text will be sent to that provider '
        'only when you press Generate. Document files are processed locally '
        'first.',
    'Используется $provider. Выбранный исходный текст будет отправлен '
        'провайдеру только после нажатия «Сгенерировать». Файлы документов '
        'сначала обрабатываются локально.',
  );
  String get sourceContent => _t('Source content', 'Исходный материал');
  String get sourceContentSubtitle => _t(
    'Notes, a topic explanation, or a study document',
    'Заметки, объяснение темы или учебный документ',
  );
  String get text => _t('Text', 'Текст');
  String get document => _t('Document', 'Документ');
  String get importPdfTxtMd => _t(
    'Import a PDF, TXT or Markdown file',
    'Импортируйте PDF, TXT или Markdown',
  );
  String extractedCharacters(int count, bool truncated) => isRussian
      ? 'Извлечено: ${characterCount(count)}${truncated ? ' (обрезано)' : ''}'
      : '${characterCount(count)} extracted${truncated ? ' (truncated)' : ''}';
  String get extracting => _t('Extracting…', 'Извлечение…');
  String get chooseFile => _t('Choose file', 'Выбрать файл');
  String get filesStayLocal => _t(
    'Files stay on this device until you press Generate. Scanned PDFs without '
        'selectable text are not supported (no OCR).',
    'Файлы остаются на устройстве до нажатия «Сгенерировать». Сканированные '
        'PDF без текстового слоя не поддерживаются (без OCR).',
  );
  String get studyNotes =>
      _t('Study notes or explanation', 'Учебные заметки или объяснение');
  String get studyNotesHint => _t(
    'Paste notes, a topic explanation or anything you want to turn into '
        'active-recall cards…',
    'Вставьте заметки, объяснение темы или что угодно, что нужно превратить '
        'в карточки для активного повторения…',
  );
  String get focusTopic =>
      _t('Focus topic (optional)', 'Фокус темы (необязательно)');
  String get focusTopicHint => _t(
    'e.g. only the causes of the French Revolution',
    'например, только причины Французской революции',
  );
  String get generationSettings =>
      _t('Generation settings', 'Настройки генерации');
  String get targetDeck => _t('Target deck', 'Целевая колода');
  String get createCollectionFirst => _t(
    'Create a collection first. The Collections tab is ready when you are.',
    'Сначала создайте коллекцию. Вкладка «Коллекции» уже ждёт.',
  );
  String get cardsToGenerate =>
      _t('Cards to generate', 'Карточек для генерации');
  String get format => _t('Format', 'Формат');
  String get basicFormat => _t(
    'One independently scheduled card per note.',
    'Одна независимо запланированная карточка на заметку.',
  );
  String get reversedFormat => _t(
    'Each note produces two cards, one per direction.',
    'Каждая заметка создаёт две карточки — по одной в каждом направлении.',
  );
  String get clozeFormat => _t(
    'Each cloze deletion produces an independently scheduled card.',
    'Каждый пропуск создаёт независимо запланированную карточку.',
  );
  String get sourceLanguage => _t('Source language', 'Язык источника');
  String get outputLanguage => _t('Output language', 'Язык результата');
  String get generating => _t('Generating…', 'Генерация…');
  String get generateCards => _t('Generate cards', 'Сгенерировать карточки');
  String get generateAgain => _t('Generate again', 'Сгенерировать снова');
  String get reviewGeneratedCards =>
      _t('Review generated cards', 'Проверьте сгенерированные карточки');
  String generatedSummary(int generated, int selected, int planned) => isRussian
      ? 'Создано: $generated · выбрано: $selected · будет сохранено: '
            '${cardCount(planned)}'
      : '$generated generated · $selected selected · ${cardCount(planned)} '
            'will be saved';
  String saveCardsTo(String deck) =>
      _t('Save cards to $deck', 'Сохранить карточки в «$deck»');
  String saveCountTo(int count, String deck) => isRussian
      ? 'Сохранить ${cardCount(count)} в «$deck»'
      : 'Save ${cardCount(count)} to $deck';
  String get saveCards => _t('Save cards', 'Сохранить карточки');
  String saveCardsQuestion(int count, String deck) => isRussian
      ? 'Сохранить ${cardCount(count)} в «$deck»?'
      : 'Save ${cardCount(count)} to $deck?';
  String saveCardsConfirm(int notes, int planned) => isRussian
      ? '$notes заметок будут добавлены. Ничего не сохраняется до подтверждения.'
      : '$notes ${notes == 1 ? 'note' : 'notes'} will be added. '
            '${planned > notes ? 'Reversed and cloze notes generate independently scheduled sibling cards. ' : ''}'
            'Nothing is saved until you confirm.';
  String get possibleDuplicate =>
      _t('Possible duplicate', 'Возможный дубликат');
  String get editGeneratedCard =>
      _t('Edit generated card', 'Изменить сгенерированную карточку');
  String get removeGeneratedCard =>
      _t('Remove generated card', 'Удалить сгенерированную карточку');
  String get applyChanges => _t('Apply', 'Применить');
  String get aiGenerationCancelled =>
      _t('Generation cancelled.', 'Генерация отменена.');
  String aiGenerationFailed(Object error) =>
      _t('AI generation failed: $error', 'Ошибка генерации ИИ: $error');
  String get applyProviderConfigured =>
      _t('AI provider configured.', 'Провайдер ИИ настроен.');
  String get chooseCollectionFirst => _t(
    'Choose a collection for the new cards.',
    'Выберите коллекцию для новых карточек.',
  );
  String get addSourceFirst => _t(
    'Add some notes, a topic or a document first.',
    'Сначала добавьте заметки, тему или документ.',
  );
  String truncatedSource(int count) => _t(
    'Only the first $count characters were sent.',
    'Отправлены только первые $count символов.',
  );
  String duplicatesWarning(int count) => isRussian
      ? '$count сгенерированных карточек похожи на существующие или друг на '
            'друга. Они не выбраны по умолчанию.'
      : '$count generated ${count == 1 ? 'card looks' : 'cards look'} similar '
            'to existing cards or each other. They are unselected by default.';
  String get couldNotExtractDocument =>
      _t('Could not extract that document.', 'Не удалось извлечь документ.');
  String savedCardsTo(int count, String deck) => isRussian
      ? 'Сохранено карточек: $count в «$deck». Просмотрите их в коллекции или '
            'начните сессию.'
      : 'Saved ${cardCount(count)} to $deck. Review them in the collection or '
            'start a study session.';
  String savedThenFailed(int count, Object error) => isRussian
      ? 'Сохранено карточек: $count, затем ошибка: $error'
      : 'Saved $count cards, then failed: $error';
  String get retryGeneration => _t('Retry', 'Повторить');
  String get configureAiTitle => _t('AI provider', 'Провайдер ИИ');
  String get aiProviderIntro => _t(
    'KnowIt supports OpenAI-compatible chat completion endpoints. Provider '
        'metadata is stored locally; the API key uses the platform secure '
        'storage and is never added to backups.',
    'KnowIt поддерживает чат-endpoints, совместимые с OpenAI. Данные '
        'провайдера хранятся локально; ключ API использует защищённое '
        'хранилище платформы и никогда не попадает в резервные копии.',
  );
  String get baseUrl => _t('Base URL', 'Базовый URL');
  String get model => _t('Model', 'Модель');
  String get replaceApiKey =>
      _t('Replace API key (optional)', 'Заменить ключ API (необязательно)');
  String get apiKey => _t('API key', 'Ключ API');
  String get keyAlreadyStored =>
      _t('A key is already stored securely', 'Ключ уже сохранён безопасно');
  String get showKey => _t('Show key', 'Показать ключ');
  String get hideKey => _t('Hide key', 'Скрыть ключ');
  String get aiKeyWarning => _t(
    'Client-side API keys can be extracted from a device. For shared or '
        'commercial use, connect through your own authenticated backend proxy '
        'with usage limits.',
    'Ключи API на клиенте можно извлечь с устройства. Для общего или '
        'коммерческого использования подключайтесь через собственный '
        'аутентифицированный прокси с лимитами.',
  );
  String get removeAiConfiguration =>
      _t('Remove AI configuration?', 'Удалить настройки ИИ?');
  String get removeAiConfigurationBody => _t(
    'The stored API key and model will be removed. Your flashcards are not '
        'affected.',
    'Сохранённый ключ API и модель будут удалены. Карточки не пострадают.',
  );
  String get saveAndTest => _t('Save & test', 'Сохранить и проверить');
  String get testing => _t('Testing…', 'Проверка…');
  String get enterApiKey => _t(
    'Enter an API key to enable AI generation.',
    'Введите ключ API, чтобы включить генерацию ИИ.',
  );
  String couldNotSaveAi(Object error) => _t(
    'Could not save AI settings: $error',
    'Не удалось сохранить настройки ИИ: $error',
  );
  String get aiConnectionSucceeded => _t(
    'AI provider connection succeeded.',
    'Подключение к провайдеру ИИ успешно.',
  );
  String aiConnectionFailed(Object error) =>
      _t('AI connection failed: $error', 'Ошибка подключения к ИИ: $error');

  // ---------------------------------------------------------------------------
  // Backup / Anki / notifications
  // ---------------------------------------------------------------------------
  String get exportAnkiTitle => _t('Export to Anki', 'Экспорт в Anki');
  String get scopeAllCollections => _t('All collections', 'Все коллекции');
  String get exportAnkiQuestion =>
      _t('Export Anki package?', 'Экспортировать пакет Anki?');
  String get exportAnkiBody => _t(
    'The APKG contains decks, notes, basic/reversed/cloze cards, tags and '
        'media. FSRS scheduling and review history are not part of this format '
        'and will not be transferred: every exported card is new.\n\n'
        'The package uses the classic Anki schema. It is validated '
        'structurally in tests, but actual import into every Anki version has '
        'not been verified.',
    'APKG содержит колоды, заметки, базовые/обратные/пропущенные карточки, '
        'теги и медиа. Планирование FSRS и история повторений не входят в этот '
        'формат и не переносятся: каждая экспортированная карточка новая.\n\n'
        'Пакет использует классическую схему Anki. Он проверяется структурно '
        'в тестах, но реальный импорт во все версии Anki не проверялся.',
  );
  String get ankiPackageReady => _t('Anki package ready', 'Пакет Anki готов');
  String get saveApkg => _t('Save .apkg', 'Сохранить .apkg');
  String get ankiPackageSaved =>
      _t('Anki package saved.', 'Пакет Anki сохранён.');
  String get ankiPackageNotSaved => _t(
    'The package was not saved. Try again or free up storage.',
    'Пакет не сохранён. Повторите попытку или освободите место.',
  );
  String ankiExportFailed(Object error) =>
      _t('Anki export failed: $error', 'Ошибка экспорта Anki: $error');
  String ankiImportSummary(String summary) =>
      _t('Anki import: $summary', 'Импорт Anki: $summary');
  String ankiImportFailed(Object error) =>
      _t('Anki import failed: $error', 'Ошибка импорта Anki: $error');
  String get exportBackupTitle =>
      _t('Export backup', 'Экспорт резервной копии');
  String get copyJson => _t('Copy JSON', 'Копировать JSON');
  String get copyJsonDone =>
      _t('Backup JSON copied', 'JSON резервной копии скопирован');
  String get saveAs => _t('Save as…', 'Сохранить как…');
  String get backupSaved => _t('Backup saved', 'Резервная копия сохранена');
  String get backupNotSaved => _t(
    'Backup was not saved. Use Copy JSON instead.',
    'Резервная копия не сохранена. Используйте «Копировать JSON».',
  );
  String get importBackupTitle => _t('Import backup', 'Импорт резервной копии');
  String get importBackupIntro => _t(
    'Paste a KnowIt JSON backup. Merge keeps your current data and adds the '
        'imported records; replace overwrites everything.',
    'Вставьте JSON резервную копию KnowIt. Объединение сохраняет текущие данные '
        'и добавляет импортированные записи; замена перезаписывает всё.',
  );
  String get chooseBackupFile => _t('Choose backup file', 'Выбрать файл копии');
  String get importing => _t('Importing…', 'Импорт…');
  String get merge => _t('Merge', 'Объединить');
  String get replace => _t('Replace', 'Заменить');
  String get replaceAllData => _t('Replace all data?', 'Заменить все данные?');
  String get replaceAllDataBody => _t(
    'This deletes every current collection, card and review, then restores the '
        'imported backup. Export a backup first if you are unsure.',
    'Это удалит все текущие коллекции, карточки и повторения, затем восстановит '
        'импортированную копию. Если не уверены, сначала экспортируйте копию.',
  );
  String importedSummary(String summary) =>
      _t('Imported: $summary', 'Импортировано: $summary');
  String restoredSummary(String summary) =>
      _t('Restored: $summary', 'Восстановлено: $summary');
  String importFailed(Object error) =>
      _t('Import failed: $error', 'Ошибка импорта: $error');
  String get newBackup => _t('New backup', 'Новая копия');
  String get noBackupFiles =>
      _t('No backup files yet', 'Файлов резервных копий пока нет');
  String get noBackupFilesMessage => _t(
    'Create a backup to keep a restore point outside the app database.',
    'Создайте копию, чтобы иметь точку восстановления вне базы приложения.',
  );
  String get savingUnavailable => _t(
    'Saving files is not available on this platform.',
    'Сохранение файлов недоступно на этой платформе.',
  );
  String backupSavedPath(String path) =>
      _t('Backup saved: $path', 'Копия сохранена: $path');
  String get restoreBackupTitle =>
      _t('Restore this backup?', 'Восстановить эту копию?');
  String get restoreBackupBody => _t(
    'Your current data will be replaced by the contents of this file.',
    'Текущие данные будут заменены содержимым этого файла.',
  );
  String get deleteFile => _t('Delete file', 'Удалить файл');
  String get restoreLabel => _t('Restore', 'Восстановить');
  String get couldNotReadBackup => _t(
    'Could not read that backup.',
    'Не удалось прочитать резервную копию.',
  );
  String restoreFailed(Object error) =>
      _t('Restore failed: $error', 'Ошибка восстановления: $error');
  String get ankiPreviewTitle =>
      _t('Anki import preview', 'Предпросмотр импорта Anki');
  String get ankiImportCouldNotRead => _t(
    'Could not read this Anki package.',
    'Не удалось прочитать пакет Anki.',
  );
  String get ankiDecks => _t('Decks', 'Колоды');
  String get ankiSampleCards => _t('Sample cards', 'Примеры карточек');
  String get skipDuplicates =>
      _t('Skip likely duplicates', 'Пропускать вероятные дубликаты');
  String get skipDuplicatesSubtitle => _t(
    'Notes matching existing cards in the same library are not imported.',
    'Заметки, совпадающие с существующими карточками в этой библиотеке, '
        'не импортируются.',
  );
  String moreNotices(int count) =>
      isRussian ? 'Ещё уведомлений: $count' : '+$count more notices';
  String moreDecks(int count) =>
      isRussian ? 'Ещё колод: $count' : '+$count more decks';
  String get notificationTitle =>
      _t('Time for a quick review', 'Время для быстрого повторения');
  String get notificationBody => _t(
    'A few minutes today keeps your cards fresh.',
    'Несколько минут сегодня — и карточки останутся свежими.',
  );
  String get notificationChannel =>
      _t('Study reminders', 'Напоминания об учёбе');
  String get notificationChannelDescription => _t(
    'Daily reminders to review your flashcards.',
    'Ежедневные напоминания повторить карточки.',
  );

  // Validation and model-facing messages.
  String get frontCannotBeEmpty => _t(
    'Front side cannot be empty.',
    'Лицевая сторона не может быть пустой.',
  );
  String get backCannotBeEmpty => _t(
    'Back side cannot be empty.',
    'Обратная сторона не может быть пустой.',
  );
  String get clozeNeedsDeletion => _t(
    'Cloze cards need at least one {{c1::deletion}}.',
    'Карточкам с пропусками нужен хотя бы один {{c1::пропуск}}.',
  );
  String get chooseDeck =>
      _t('Choose a deck for this card.', 'Выберите колоду для карточки.');
  String get untitledDeck => _t('Untitled deck', 'Колода без названия');
  String get unknown => _t('Unknown', 'Неизвестно');
  String learningStateLabel(int state) => switch (state) {
    0 => _t('New', 'Новая'),
    1 => _t('Learning', 'Изучается'),
    2 => _t('Review', 'Повторение'),
    3 => _t('Relearning', 'Переобучение'),
    _ => unknown,
  };
  String cardTypeLabel(int type) => switch (type) {
    0 => _t('Basic', 'Базовая'),
    1 => _t('Reversed', 'Обратная'),
    2 => _t('Cloze deletion', 'Пропуск'),
    _ => unknown,
  };
  String cardTypeDescription(int type) => switch (type) {
    0 => _t(
      'Front shows the question, back shows the answer.',
      'Лицевая сторона показывает вопрос, обратная — ответ.',
    ),
    1 => _t(
      'Creates two cards with independent schedules: front→back and '
          'back→front.',
      'Создаёт две карточки с независимым расписанием: лицо→оборот и '
          'оборот→лицо.',
    ),
    2 => _t(
      'Every {{c1::...}} deletion becomes a separately scheduled card.',
      'Каждый пропуск {{c1::...}} становится отдельно запланированной карточкой.',
    ),
    _ => unknown,
  };

  // Statistics suggestions
  String get suggestionCreateDeck =>
      _t('Create your first deck', 'Создайте первую колоду');
  String get suggestionCreateDeckMessage => _t(
    'Organise your cards into decks, then study them with spaced repetition.',
    'Организуйте карточки в колоды, затем изучайте их с интервальным повторением.',
  );
  String get suggestionCreateDeckAction => _t('Create deck', 'Создать колоду');
  String get suggestionAddCard =>
      _t('Add your first card', 'Добавьте первую карточку');
  String get suggestionAddCardMessage => _t(
    'A deck without cards is just a nice idea. Add a question and an answer to '
        'get started.',
    'Колода без карточек — просто идея. Добавьте вопрос и ответ, чтобы начать.',
  );
  String get suggestionAddCardAction => _t('Add card', 'Добавить карточку');
  String dueTodaySuggestionTitle(int count) =>
      isRussian ? 'Сегодня к повторению: $count' : '$count cards are due today';
  String get dueTodaySuggestionMessage => _t(
    'A short review now keeps your schedule manageable.',
    'Короткое повторение сейчас поможет держать расписание под контролем.',
  );
  String dueTodaySuggestionDeck(String name, int count) => isRussian
      ? 'Больше всего карточек ждёт в «$name» ($count).'
      : '$name has the most cards waiting ($count).';
  String slippingSuggestionTitle(int count) => isRussian
      ? 'Карточки, которые часто забываются: $count+'
      : '$count+ cards keep slipping';
  String slippingSuggestionMessage(String deck) => isRussian
      ? 'Попробуйте режим сложных карточек${deck.isEmpty ? '' : ' в «$deck»'}, '
            'чтобы укрепить их.'
      : 'Try the difficult-cards mode${deck.isEmpty ? '' : ' in $deck'} to '
            'strengthen them.';
  String get practiceSuggestionAction => _t('Practice', 'Практика');
  String retentionSuggestionTitle(int percent) =>
      isRussian ? 'Удержание: $percent%' : 'Retention is $percent%';
  String retentionSuggestionMessage(int target) => isRussian
      ? 'Ваша цель — $target%. Более частые повторения или более короткие '
            'карточки могут помочь.'
      : 'Your target is $target%. More frequent reviews or shorter cards may '
            'help.';
  String get reviewSuggestionAction => _t('Review', 'Повторить');
  String streakSuggestionTitle(int days) =>
      isRussian ? 'Сохраните серию: $days дн.' : 'Keep your $days-day streak';
  String get streakSuggestionMessage => _t(
    'One review today is enough to keep the habit alive.',
    'Одного повторения сегодня достаточно, чтобы сохранить привычку.',
  );
  String goalSuggestionTitle(int done, int goal) =>
      isRussian ? 'Цель на день: $done/$goal' : 'Daily goal: $done/$goal';
  String goalSuggestionMessage(int remaining) => isRussian
      ? 'До цели дня осталось: ${reviewCount(remaining)}.'
      : 'You are ${reviewCount(remaining)} away from today’s goal.';
  String get goalReachedTitle =>
      _t('Daily goal reached', 'Цель дня достигнута');
  String get goalReachedMessage => _t(
    'Nice work. Extra practice is optional — your future self will thank you.',
    'Отличная работа. Дополнительная практика необязательна — будущий вы '
        'поблагодарите себя.',
  );

  // Onboarding / startup
  String get startupLibraryErrorTitle => _t(
    'KnowIt could not open its local library',
    'KnowIt не удалось открыть локальную библиотеку',
  );
  String get startupLibraryErrorBody => _t(
    'Your data has not been deleted. Close the app and reopen it. If the '
        'problem continues, the Hive database in the app data folder may be '
        'corrupted — restore it from a backup instead of deleting it.',
    'Ваши данные не удалены. Закройте и снова откройте приложение. Если проблема '
        'повторяется, база Hive в папке данных приложения может быть повреждена — '
        'восстановите её из резервной копии, а не удаляйте.',
  );
}

extension StudyModeLocalization on StudyMode {
  String localizedLabel(AppLocalizations l10n) => l10n.studyModeLabel(this);
  String localizedShortLabel(AppLocalizations l10n) =>
      l10n.studyModeShortLabel(this);
  String localizedDescription(AppLocalizations l10n) =>
      l10n.studyModeDescription(this);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) {
    final localizations = AppLocalizations(
      Locale(locale.languageCode == 'ru' ? 'ru' : 'en'),
    );
    AppLocalizations._current = localizations;
    return SynchronousFuture(localizations);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
