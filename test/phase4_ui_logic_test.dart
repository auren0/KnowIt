import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/screens/settings_screen.dart';
import 'package:knowit/screens/study_screen.dart';
import 'package:knowit/services/scheduler_service.dart';
import 'package:knowit/services/settings_service.dart';
import 'package:knowit/theme/theme.dart';

import 'test_helpers.dart';

Widget _testApp({
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

  group('Part 1: Font Consistency Across All Buttons and Themes', () {
    test('theme assigns selected font family to all button themes', () {
      for (final font in [AppFontFamily.nunito, AppFontFamily.jetBrainsMono]) {
        final theme = buildKnowItTheme(Brightness.light, font: font);

        // Core TextTheme
        expect(theme.textTheme.bodyMedium?.fontFamily, font.family);
        expect(theme.textTheme.labelLarge?.fontFamily, font.family);
        expect(theme.textTheme.headlineMedium?.fontFamily, font.family);

        // Button Themes
        final filledStyle = theme.filledButtonTheme.style;
        final filledTextStyle = filledStyle?.textStyle?.resolve({});
        expect(filledTextStyle?.fontFamily, font.family);
        expect(filledTextStyle?.fontFamilyFallback, contains('AppleColorEmoji'));

        final elevatedStyle = theme.elevatedButtonTheme.style;
        final elevatedTextStyle = elevatedStyle?.textStyle?.resolve({});
        expect(elevatedTextStyle?.fontFamily, font.family);
        expect(elevatedTextStyle?.fontFamilyFallback, contains('AppleColorEmoji'));

        final outlinedStyle = theme.outlinedButtonTheme.style;
        final outlinedTextStyle = outlinedStyle?.textStyle?.resolve({});
        expect(outlinedTextStyle?.fontFamily, font.family);
        expect(outlinedTextStyle?.fontFamilyFallback, contains('AppleColorEmoji'));

        final textStyle = theme.textButtonTheme.style;
        final textBtnTextStyle = textStyle?.textStyle?.resolve({});
        expect(textBtnTextStyle?.fontFamily, font.family);
        expect(textBtnTextStyle?.fontFamilyFallback, contains('AppleColorEmoji'));

        final segStyle = theme.segmentedButtonTheme.style;
        final segTextStyle = segStyle?.textStyle?.resolve({});
        expect(segTextStyle?.fontFamily, font.family);

        final popupStyle = theme.popupMenuTheme.textStyle;
        expect(popupStyle?.fontFamily, font.family);

        expect(theme.dialogTheme.titleTextStyle?.fontFamily, font.family);
        expect(theme.dialogTheme.contentTextStyle?.fontFamily, font.family);
      }
    });

    testWidgets('buttons in widget tree inherit selected font at runtime', (tester) async {
      final theme = buildKnowItTheme(Brightness.light, font: AppFontFamily.jetBrainsMono);

      await tester.pumpWidget(
        _testApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Filled')),
                ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
                OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
                TextButton(onPressed: () {}, child: const Text('TextBtn')),
              ],
            ),
          ),
        ),
      );

      final filledFinder = find.widgetWithText(FilledButton, 'Filled');
      expect(filledFinder, findsOneWidget);
      final DefaultTextStyle filledDefaultText = tester.widget(
        find.descendant(of: filledFinder, matching: find.byType(DefaultTextStyle)).last,
      );
      expect(filledDefaultText.style.fontFamily, 'JetBrainsMono');

      final elevatedFinder = find.widgetWithText(ElevatedButton, 'Elevated');
      final DefaultTextStyle elevatedDefaultText = tester.widget(
        find.descendant(of: elevatedFinder, matching: find.byType(DefaultTextStyle)).last,
      );
      expect(elevatedDefaultText.style.fontFamily, 'JetBrainsMono');
    });
  });

  group('Part 2: 12 Accent Colors Palette', () {
    test('all 12 accent colors are present with balanced values', () {
      expect(AccentColor.values.length, 12);
      final names = AccentColor.values.map((c) => c.name).toSet();
      expect(names, {
        'yellow',
        'blue',
        'green',
        'purple',
        'orange',
        'red',
        'pink',
        'cyan',
        'teal',
        'indigo',
        'mint',
        'coral',
      });
    });

    test('all 12 accent colors serialize and deserialize safely', () {
      for (final color in AccentColor.values) {
        expect(AccentColor.fromName(color.name), color);
        expect(AccentColor.fromName(color.storageName), color);
        expect(AccentColor.fromName(color.storageName.toLowerCase()), color);

        final settings = AppSettings(accentColor: color);
        final map = settings.toMap();
        final restored = AppSettings.fromMap(map);
        expect(restored.accentColor, color);
      }
      expect(AccentColor.fromName('non_existent'), AccentColor.yellow);
      expect(AccentColor.fromName(null), AccentColor.yellow);
    });

    test('each accent color produces a valid and distinct ColorScheme', () {
      final seeds = <Color>{};
      for (final color in AccentColor.values) {
        seeds.add(color.seed);
        final light = buildKnowItTheme(Brightness.light, accent: color);
        final dark = buildKnowItTheme(Brightness.dark, accent: color);
        expect(light.colorScheme.primary, isNotNull);
        expect(dark.colorScheme.primary, isNotNull);
      }
      expect(seeds.length, 12);
    });

    testWidgets('all 12 swatches render in settings with localized names', (tester) async {
      await tester.pumpWidget(
        _testApp(
          home: const Scaffold(body: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      for (final color in AccentColor.values) {
        expect(find.byTooltip(color.storageName), findsOneWidget);
      }
    });
  });

  group('Part 3: AI Settings Button Alignment and Layout', () {
    testWidgets('configure AI button has 48px min height and proper shape', (tester) async {
      await tester.pumpWidget(
        _testApp(
          home: const Scaffold(body: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final textFinder = find.text('Configure AI');
      await tester.scrollUntilVisible(textFinder, 300);
      expect(textFinder, findsOneWidget);

      final btnFinder = find.ancestor(of: textFinder, matching: find.byType(FilledButton));
      expect(btnFinder, findsOneWidget);

      final FilledButton button = tester.widget(btnFinder);
      expect(button.style?.minimumSize?.resolve({}), const Size.fromHeight(48));
      final shape = button.style?.shape?.resolve({}) as RoundedRectangleBorder?;
      expect(shape?.borderRadius, BorderRadius.circular(14));
    });

    testWidgets('configure AI button renders properly in Russian locale', (tester) async {
      await tester.pumpWidget(
        _testApp(
          locale: const Locale('ru'),
          home: const Scaffold(body: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final textFinder = find.text('Настроить ИИ');
      await tester.scrollUntilVisible(textFinder, 300);
      expect(textFinder, findsOneWidget);

      final btnFinder = find.ancestor(of: textFinder, matching: find.byType(FilledButton));
      expect(btnFinder, findsOneWidget);
    });
  });

  group('Part 4: Anki-Style Instant Answer Reveal vs Flip Mode', () {
    testWidgets('Flip Mode: Initially shows question, flips on reveal', (tester) async {
      await tester.runAsync(() async {
        await SettingsService.save(
          const AppSettings(answerRevealMode: AnswerRevealMode.flip),
        );
      });

      final card = makeCard(
        collectionId: 'deck-1',
        front: 'What is the speed of light?',
        back: '299,792,458 m/s',
      );

      await tester.pumpWidget(
        _testApp(
          home: StudyScreen(
            title: 'Test Deck',
            deckIds: const ['deck-1'],
            mode: StudyMode.srs,
            cards: [card],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Front content visible
      expect(find.text('What is the speed of light?'), findsOneWidget);
      expect(find.text('299,792,458 m/s'), findsNothing);
      expect(find.text('Show answer'), findsOneWidget);

      // Tap Show Answer
      await tester.tap(find.text('Show answer'));
      await tester.pumpAndSettle();

      // In flip mode, the back is shown
      expect(find.text('299,792,458 m/s'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
    });

    testWidgets('Instant Mode: Front remains visible above divider when answer is revealed', (tester) async {
      await tester.runAsync(() async {
        await SettingsService.save(
          const AppSettings(answerRevealMode: AnswerRevealMode.instant),
        );
      });

      final card = makeCard(
        collectionId: 'deck-1',
        front: 'Front Question Alpha',
        back: 'Back Answer Omega',
      );

      await tester.pumpWidget(
        _testApp(
          home: StudyScreen(
            title: 'Instant Deck',
            deckIds: const ['deck-1'],
            mode: StudyMode.srs,
            cards: [card],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Before reveal: Front is shown, back is hidden
      expect(find.text('Front Question Alpha'), findsOneWidget);
      expect(find.text('Back Answer Omega'), findsNothing);
      expect(find.text('Show answer'), findsOneWidget);

      // Reveal answer
      await tester.tap(find.text('Show answer'));
      await tester.pumpAndSettle();

      // After reveal in Anki-style instant mode:
      // 1. Front content remains visible!
      expect(find.text('Front Question Alpha'), findsOneWidget);
      // 2. Back content appears below divider!
      expect(find.text('Back Answer Omega'), findsOneWidget);
      // 3. Divider exists between them
      expect(find.byType(Divider), findsWidgets);
      // 4. Rating buttons accessible
      expect(find.text('Again'), findsOneWidget);
      expect(find.text('Good'), findsOneWidget);
      expect(find.text('Easy'), findsOneWidget);
    });

    testWidgets('Instant Mode with Cloze card keeps question and shows completed answer', (tester) async {
      await tester.runAsync(() async {
        await SettingsService.save(
          const AppSettings(answerRevealMode: AnswerRevealMode.instant),
        );
      });

      final card = CardItem(
        collectionId: 'deck-1',
        type: CardType.cloze,
        frontText: 'The capital of {{c1::France}} is Paris.',
        backText: 'Located on the river Seine.',
        clozeIndex: 1,
      );

      await tester.pumpWidget(
        _testApp(
          home: StudyScreen(
            title: 'Cloze Deck',
            deckIds: const ['deck-1'],
            mode: StudyMode.srs,
            cards: [card],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Before reveal: Deletion is hidden as [...]
      expect(find.textContaining('The capital of [...] is Paris.'), findsOneWidget);
      expect(find.text('Show answer'), findsOneWidget);

      // Reveal answer
      await tester.tap(find.text('Show answer'));
      await tester.pumpAndSettle();

      // After reveal:
      // Front question with [...] remains visible at the top
      expect(find.textContaining('The capital of [...] is Paris.'), findsOneWidget);
      // Completed answer with highlighted deletion appears below divider
      expect(find.textContaining('The capital of France is Paris.'), findsOneWidget);
      expect(find.textContaining('Located on the river Seine.'), findsOneWidget);
      expect(find.text('Again'), findsOneWidget);
    });

    testWidgets('Sibling Cloze cards show distinct active deletions', (tester) async {
      await tester.runAsync(() async {
        await SettingsService.save(
          const AppSettings(answerRevealMode: AnswerRevealMode.instant),
        );
      });

      final card2 = CardItem(
        collectionId: 'deck-1',
        type: CardType.cloze,
        frontText: '{{c1::Berlin}} is in {{c2::Germany}}.',
        backText: '',
        clozeIndex: 2,
      );

      await tester.pumpWidget(
        _testApp(
          home: StudyScreen(
            title: 'Sibling Deck',
            deckIds: const ['deck-1'],
            mode: StudyMode.srs,
            cards: [card2],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Before reveal: c1 (Berlin) is visible, c2 is hidden as [...]
      expect(find.textContaining('Berlin is in [...].'), findsOneWidget);

      await tester.tap(find.text('Show answer'));
      await tester.pumpAndSettle();

      // After reveal: Front remains visible, completed answer appears
      expect(find.textContaining('Berlin is in [...].'), findsOneWidget);
      expect(find.textContaining('Berlin is in Germany.'), findsOneWidget);
    });
  });

  group('Part 5: Scheduling and Reference Invariants', () {
    test('scheduler produces deterministic intervals matching FSRS specification', () {
      const scheduler = SchedulerService();
      final now = DateTime(2026, 11, 22, 10, 0);
      const settings = AppSettings(
        learningStepsMinutes: [1, 10],
        relearningStepsMinutes: [10],
        desiredRetention: 0.9,
      );

      final card = CardItem(
        frontText: 'Invariant question',
        backText: 'Invariant answer',
        collectionId: 'deck',
      );

      final again = scheduler.schedule(card: card, rating: fsrs.Rating.again, settings: settings, now: now);
      final hard = scheduler.schedule(card: card, rating: fsrs.Rating.hard, settings: settings, now: now);
      final good = scheduler.schedule(card: card, rating: fsrs.Rating.good, settings: settings, now: now);
      final easy = scheduler.schedule(card: card, rating: fsrs.Rating.easy, settings: settings, now: now);

      expect(again.card.state, CardLearningState.learning);
      expect(hard.card.state, CardLearningState.learning);
      expect(good.card.state, CardLearningState.learning);
      expect(easy.card.state, CardLearningState.review);

      expect(again.interval, const Duration(minutes: 1));
      expect(good.interval, const Duration(minutes: 10));
      expect(easy.interval.inDays, greaterThanOrEqualTo(1));
    });
  });
}
