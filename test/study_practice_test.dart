import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/screens/study_screen.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/settings_service.dart';
import 'package:knowit/theme/theme.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(initTestHive);
  setUp(initTestHive);

  testWidgets('cram mode logs practice without changing the schedule', (
    tester,
  ) async {
    final deck = makeDeck(name: 'Practice');
    final card = makeCard(
      collectionId: deck.id,
      front: 'Practice question',
      back: 'Practice answer',
    );
    await tester.runAsync(() async {
      await SettingsService.save(const AppSettings());
      await HiveService.createCollection(deck);
      await HiveService.addCard(card);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKnowItTheme(Brightness.light),
        home: StudyScreen(
          deckIds: [deck.id],
          title: deck.name,
          mode: StudyMode.cram,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Practice question'), findsOneWidget);
    expect(find.textContaining('will not be changed'), findsOneWidget);

    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Again'));
    await tester.pump();
    await pumpUntil(tester, find.text('Session complete'));

    final stored = HiveService.getCard(card.id)!;
    expect(stored.state, CardLearningState.newCard);
    expect(stored.reps, 0);
    expect(stored.due, isNull);
    expect(stored.stability, isNull);
    final logs = HiveService.getLogsForCard(card.id);
    expect(logs.length, 1);
    expect(logs.single.mode, StudyMode.cram.name);
    expect(logs.single.rating, 1);
  });
}
