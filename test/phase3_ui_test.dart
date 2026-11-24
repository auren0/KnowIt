import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/screens/create_collection_screen.dart';
import 'package:knowit/screens/study_screen.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/settings_service.dart';
import 'package:knowit/services/stats_service.dart';
import 'package:knowit/theme/theme.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/grouped_list.dart';
import 'package:knowit/widgets/insights.dart';
import 'package:knowit/widgets/study_mode_sheet.dart';

import 'test_helpers.dart';

Widget _localizedApp({
  required Widget home,
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: theme ?? buildKnowItTheme(Brightness.light),
    home: home,
  );
}

void main() {
  setUpAll(initTestHive);
  setUp(initTestHive);
  tearDownAll(closeTestHive);

  test('new settings default to English, yellow, Nunito and flip reveal', () {
    final settings = AppSettings.fromMap(const {});
    expect(settings.language, AppLanguage.en);
    expect(settings.accentColor, AccentColor.yellow);
    expect(settings.fontFamily, AppFontFamily.nunito);
    expect(settings.answerRevealMode, AnswerRevealMode.flip);
  });

  test('personalization settings survive serialization', () {
    const settings = AppSettings(
      language: AppLanguage.ru,
      accentColor: AccentColor.purple,
      fontFamily: AppFontFamily.jetBrainsMono,
      answerRevealMode: AnswerRevealMode.instant,
    );
    final restored = AppSettings.fromFlatMap(settings.toFlatMap());
    expect(restored.language, AppLanguage.ru);
    expect(restored.accentColor, AccentColor.purple);
    expect(restored.fontFamily, AppFontFamily.jetBrainsMono);
    expect(restored.answerRevealMode, AnswerRevealMode.instant);
    expect(restored, settings);
  });

  test('personalization persists through SettingsService', () async {
    await SettingsService.save(
      const AppSettings(
        language: AppLanguage.ru,
        accentColor: AccentColor.blue,
        fontFamily: AppFontFamily.jetBrainsMono,
      ),
    );
    expect(SettingsService.value.language, AppLanguage.ru);
    expect(SettingsService.value.accentColor, AccentColor.blue);
    expect(SettingsService.value.fontFamily, AppFontFamily.jetBrainsMono);
  });

  test('theme applies the selected accent and font', () {
    final yellow = buildKnowItTheme(Brightness.light);
    final blue = buildKnowItTheme(Brightness.light, accent: AccentColor.blue);
    expect(yellow.colorScheme.primary, isNot(blue.colorScheme.primary));
    final mono = buildKnowItTheme(
      Brightness.light,
      font: AppFontFamily.jetBrainsMono,
    );
    expect(mono.textTheme.bodyMedium?.fontFamily, 'JetBrainsMono');
  });

  test('year heatmap uses real logs and handles leap day', () {
    final logs = [
      ReviewLog(
        cardId: 'card',
        collectionId: 'deck',
        rating: 3,
        reviewedAt: DateTime(2024, 2, 29, 12),
      ),
      ReviewLog(
        cardId: 'card',
        collectionId: 'deck',
        rating: 3,
        reviewedAt: DateTime(2024, 3, 1, 12),
      ),
      ReviewLog(
        cardId: 'card',
        collectionId: 'deck',
        rating: 3,
        reviewedAt: DateTime(2023, 2, 28, 12),
      ),
    ];
    final heatmap = const StatsService().heatmapForYear(logs, year: 2024);
    expect(heatmap['2024-02-29'], 1);
    expect(heatmap['2024-03-01'], 1);
    expect(heatmap.containsKey('2023-02-28'), isFalse);
  });

  testWidgets('English is the default and Russian updates immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(
        home: Builder(builder: (context) => Text(context.l10n.collections)),
      ),
    );
    expect(find.text('Collections'), findsOneWidget);

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('ru'),
        home: Builder(builder: (context) => Text(context.l10n.collections)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Коллекции'), findsOneWidget);
  });

  testWidgets('instant answer reveal shows content without a flip animation', (
    tester,
  ) async {
    final deck = makeDeck(name: 'Reveal');
    final card = makeCard(
      collectionId: deck.id,
      front: 'Question?',
      back: 'Answer!',
    );
    await tester.runAsync(() async {
      await SettingsService.save(
        const AppSettings(
          learningStepsMinutes: [],
          answerRevealMode: AnswerRevealMode.instant,
        ),
      );
      await HiveService.createCollection(deck);
      await HiveService.addCard(card);
    });

    await tester.pumpWidget(
      _localizedApp(
        home: StudyScreen(deckIds: [deck.id], title: deck.name),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show answer'));
    await tester.pump();
    expect(find.text('Answer!'), findsOneWidget);
    expect(find.text('Show answer'), findsNothing);
  });

  testWidgets('grouped list rounds only the outer corners', (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        home: Scaffold(
          body: GroupedList(
            children: [
              for (var index = 0; index < 3; index++)
                ListTile(title: Text('Item $index')),
            ],
          ),
        ),
      ),
    );

    final clips = tester
        .widgetList<ClipRRect>(
          find.descendant(
            of: find.byType(GroupedList),
            matching: find.byType(ClipRRect),
          ),
        )
        .toList();
    expect(clips.length, 3);
    expect(
      clips[0].borderRadius,
      BorderRadius.vertical(top: Radius.circular(16)),
    );
    expect(clips[1].borderRadius, BorderRadius.zero);
    expect(
      clips[2].borderRadius,
      BorderRadius.vertical(bottom: Radius.circular(16)),
    );
  });

  testWidgets('heatmap year navigation stays in the past', (tester) async {
    final year = DateTime.now().year;
    final logs = [
      ReviewLog(
        cardId: 'card',
        collectionId: 'deck',
        rating: 3,
        reviewedAt: DateTime(year, 1, 2, 12),
      ),
      ReviewLog(
        cardId: 'card',
        collectionId: 'deck',
        rating: 3,
        reviewedAt: DateTime(year - 1, 6, 2, 12),
      ),
    ];

    await tester.pumpWidget(
      _localizedApp(
        home: Scaffold(
          body: SingleChildScrollView(child: YearActivityHeatmap(logs: logs)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('$year'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous year'));
    await tester.pumpAndSettle();
    expect(find.text('${year - 1}'), findsOneWidget);

    await tester.tap(find.byTooltip('Next year'));
    await tester.pumpAndSettle();
    expect(find.text('$year'), findsOneWidget);
  });

  testWidgets('Russian dialog actions fit without overflow', (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('ru'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: AppDialogActions(
                children: [
                  TextButton(onPressed: () {}, child: const Text('Отмена')),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Продолжить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Продолжить'), findsOneWidget);
  });

  testWidgets('shared dialog actions render and confirm', (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAppConfirmDialog(
                  context,
                  title: 'Delete deck?',
                  message: 'This cannot be undone.',
                  confirmLabel: 'Delete',
                  cancelLabel: 'Cancel',
                  destructive: true,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete deck?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete deck?'), findsNothing);
  });

  testWidgets('dialog actions stack safely on narrow screens', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('ru'),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAppConfirmDialog(
                  context,
                  title: 'Удалить колоду?',
                  message: 'Это действие нельзя отменить.',
                  confirmLabel: 'Удалить',
                  cancelLabel: 'Отмена',
                  destructive: true,
                ),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить колоду?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
  });

  testWidgets('study mode sheet scrolls on a short screen', (tester) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _localizedApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showStudyModeSheet(
                  context,
                  deckName: 'Biology',
                ),
                child: const Text('Modes'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Modes'));
    await tester.pumpAndSettle();
    expect(find.text('Spaced repetition'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('collection creation has one primary action and saves', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(home: const CreateCollectionScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create Collection'), findsOneWidget);
    expect(find.text('Save'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Phase 3 deck');
    await tester.pump();
    await tester.tap(find.text('Create Collection'));
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(CreateCollectionScreen).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();

    expect(
      HiveService.getAllCollections().any(
        (deck) => deck.name == 'Phase 3 deck',
      ),
      isTrue,
    );
    final created = HiveService.getAllCollections().firstWhere(
      (deck) => deck.name == 'Phase 3 deck',
    );
    expect(created.emoji, '');
  });
}
