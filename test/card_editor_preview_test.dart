import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/screens/create_card_screen.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/theme/theme.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(initTestHive);
  setUp(initTestHive);

  testWidgets('card editor shows a live preview', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final deck = makeDeck(name: 'Preview deck');
    await tester.runAsync(() async {
      await HiveService.createCollection(deck);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKnowItTheme(Brightness.light),
        home: CreateCardScreen(collectionId: deck.id),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField).at(0), 'Live question');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Live question'), findsWidgets);
    expect(find.text('LIVE PREVIEW'), findsOneWidget);
  });
}
