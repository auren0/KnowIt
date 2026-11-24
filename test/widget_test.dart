import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/screens/study_screen.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/settings_service.dart';
import 'package:knowit/theme/theme.dart';
import 'package:knowit/models/study_mode.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(initTestHive);
  setUp(initTestHive);

  testWidgets('studying persists a review, completes and can be undone', (
    tester,
  ) async {
    // Graduate immediately so a single Good completes the session.
    final deck = makeDeck(name: 'Geography');
    final card = makeCard(
      collectionId: deck.id,
      front: 'Capital of France?',
      back: 'Paris',
    );
    await tester.runAsync(() async {
      await SettingsService.save(const AppSettings(learningStepsMinutes: []));
      await HiveService.createCollection(deck);
      await HiveService.addCard(card);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKnowItTheme(Brightness.light),
        home: StudyScreen(
          deckIds: [deck.id],
          title: deck.name,
          mode: StudyMode.srs,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Capital of France?'), findsOneWidget);
    expect(find.text('Show answer'), findsOneWidget);

    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    expect(find.text('Paris'), findsOneWidget);
    expect(find.text('Again'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);

    await tester.tap(find.text('Good'));
    await tester.pump();
    await pumpUntil(tester, find.text('Session complete'));

    expect(find.text('Session complete'), findsWidgets);
    final stored = HiveService.getCard(card.id)!;
    expect(stored.state, CardLearningState.review);
    expect(stored.reps, 1);
    expect(stored.lastReview, isNotNull);
    expect(stored.due!.isAfter(DateTime.now()), isTrue);
    expect(HiveService.getLogsForCard(card.id).length, 1);

    await tester.ensureVisible(find.text('Undo last rating'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Undo last rating'));
    await tester.pump();
    await pumpUntil(tester, find.text('Paris'));

    expect(HiveService.getCard(card.id)!.state, CardLearningState.newCard);
    expect(HiveService.getLogsForCard(card.id), isEmpty);
    expect(find.text('Paris'), findsOneWidget); // answer side restored
  });
}
