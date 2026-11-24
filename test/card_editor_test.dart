import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/screens/create_card_screen.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/theme/theme.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(initTestHive);
  setUp(initTestHive);

  testWidgets('card editor validates and saves a real card', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final deck = makeDeck(name: 'History');
    await tester.runAsync(() async {
      await HiveService.createCollection(deck);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKnowItTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateCardScreen(collectionId: deck.id),
                  ),
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('New card'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Front side cannot be empty.'), findsOneWidget);
    expect(HiveService.getCardsByCollection(deck.id), isEmpty);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Who wrote Dune?');
    await tester.enterText(fields.at(1), 'Frank Herbert');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await pumpUntil(tester, find.text('Open editor'));

    expect(find.text('Open editor'), findsOneWidget);
    final cards = HiveService.getCardsByCollection(deck.id);
    expect(cards.length, 1);
    expect(cards.single.frontText, 'Who wrote Dune?');
    expect(cards.single.backText, 'Frank Herbert');
  });
}
