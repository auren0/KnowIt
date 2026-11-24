import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/theme/theme.dart';

import 'test_helpers.dart';

void main() {
  setUpAll(initTestHive);
  setUp(initTestHive);

  testWidgets('app opens on collections and navigates into a deck', (
    tester,
  ) async {
    final deck = makeDeck(name: 'Biology');
    final card = makeCard(
      collectionId: deck.id,
      front: 'What is a cell?',
      back: 'The basic unit of life',
    );
    await tester.runAsync(() async {
      await HiveService.createCollection(deck);
      await HiveService.addCard(card);
    });

    await tester.pumpWidget(const Knowit());
    await tester.pumpAndSettle();

    expect(find.text('Collections'), findsWidgets);
    expect(find.text('Biology'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('Statistics'), findsOneWidget);

    await tester.tap(find.text('Biology'));
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Cards'), findsWidgets);
    expect(find.text('Stats'), findsOneWidget);

    await tester.tap(find.text('Cards').first);
    await tester.pumpAndSettle();
    expect(find.text('What is a cell?'), findsOneWidget);
  });

  testWidgets('empty library shows a useful empty state', (tester) async {
    await tester.pumpWidget(const Knowit());
    await tester.pumpAndSettle();

    expect(find.text('No collections yet'), findsOneWidget);
    expect(find.text('New collection'), findsOneWidget);
  });

  test('cloze and reversed cards render the correct study sides', () {
    final basic = makeCard(
      collectionId: 'deck',
      type: CardType.cloze,
      front: 'The {{c1::mitochondria}} is the powerhouse.',
      back: 'Cell biology',
    );
    expect(basic.studyFront.contains('mitochondria'), isFalse);
    expect(basic.studyBack.contains('mitochondria'), isTrue);
    expect(basic.studyBack.contains('Cell biology'), isTrue);

    final reversed = makeCard(
      collectionId: 'deck',
      type: CardType.reversed,
      front: 'bonjour',
      back: 'hello',
      reverse: true,
    );
    expect(reversed.studyFront, 'hello');
    expect(reversed.studyBack, 'bonjour');
    expect(reversed.variantLabel, 'Reverse');

    expect(basic.validate(), isNull);
    final invalidCloze = makeCard(
      collectionId: 'deck',
      type: CardType.cloze,
      front: 'No deletion here',
    );
    expect(invalidCloze.validate(), isNotNull);
  });

  test('serialization keeps collection hierarchy', () {
    final deck = Collection(
      id: 'child',
      name: 'Child',
      emoji: '🧠',
      colorValue: 0xFF0000,
      parentId: 'parent',
      description: 'Desc',
    );
    final restored = Collection.fromJson(deck.toJson());
    expect(restored.parentId, 'parent');
    expect(restored.name, 'Child');
    expect(restored.description, 'Desc');
  });
}
