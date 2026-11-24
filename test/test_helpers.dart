import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/settings_service.dart';
import 'package:knowit/utils/id_generator.dart';

Directory? _tempDirectory;

/// Initializes an isolated Hive database for a test file. Safe to call from
/// every setUp; data is cleared between tests.
Future<void> initTestHive() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!HiveService.isInitialized) {
    _tempDirectory = await Directory.systemTemp.createTemp('knowit_test_');
    await HiveService.init(directory: _tempDirectory!.path);
    await SettingsService.init();
  } else {
    await HiveService.clearAllData();
  }
  await SettingsService.save(AppSettings.defaults);
}

Future<void> closeTestHive() async {
  try {
    await Hive.close().timeout(const Duration(seconds: 3));
  } on Object {
    // A widget test may still hold a box open; leaving the temp directory is
    // harmless and must not hang the test process.
  }
  final directory = _tempDirectory;
  if (directory != null) {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } on Object {
      // Best-effort cleanup only.
    }
  }
  _tempDirectory = null;
}

/// Alternates real async progress with frames until [finder] matches while
/// allowing Hive file writes to complete inside widget tests.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int attempts = 40,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
}

Collection makeDeck({
  String name = 'Biology',
  String? id,
  String? parentId,
  Color color = Colors.blue,
}) {
  return Collection(
    id: id ?? newId(),
    name: name,
    emoji: '🧪',
    colorValue: color.toARGB32(),
    parentId: parentId,
  );
}

CardItem makeCard({
  required String collectionId,
  String front = 'Question',
  String back = 'Answer',
  String? id,
  CardType type = CardType.basic,
  List<String> tags = const [],
  CardLearningState state = CardLearningState.newCard,
  double? stability,
  double? difficulty,
  DateTime? due,
  DateTime? lastReview,
  int reps = 0,
  int lapses = 0,
  int? step,
  String? noteId,
  bool reverse = false,
  int clozeIndex = 0,
}) {
  return CardItem(
    id: id ?? newId(),
    frontText: front,
    backText: back,
    collectionId: collectionId,
    type: type,
    tags: tags,
    state: state,
    step: step,
    stability: stability,
    difficulty: difficulty,
    due: due,
    lastReview: lastReview,
    reps: reps,
    lapses: lapses,
    noteId: noteId,
    reverse: reverse,
    clozeIndex: clozeIndex,
  );
}
