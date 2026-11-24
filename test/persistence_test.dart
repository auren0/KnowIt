import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/services/hive_service.dart';
import 'test_helpers.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('knowit_restart_');
    await HiveService.init(directory: dir.path);
  });
  tearDownAll(() async {
    try {
      await HiveService.close();
    } catch (_) {}
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  test('data survives a Hive close and reopen', () async {
    final deck = makeDeck(name: 'Persisted');
    await HiveService.createCollection(deck);
    final card = makeCard(collectionId: deck.id, front: 'Still here');
    await HiveService.addCard(card);
    await HiveService.addLog(
      ReviewLog(
        cardId: card.id,
        collectionId: deck.id,
        rating: 3,
        reviewedAt: DateTime.now(),
      ),
    );
    await HiveService.close();
    await HiveService.init(directory: dir.path);
    expect(HiveService.getAllCollections().single.name, 'Persisted');
    expect(HiveService.getAllCards().single.frontText, 'Still here');
    expect(HiveService.getAllLogs().length, 1);
  });
}
