import 'dart:math' as math;

import 'package:hive/hive.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/utils/id_generator.dart';

part 'card_item.g.dart';

/// The kind of flashcard the note represents.
enum CardType {
  basic,
  reversed,
  cloze;

  String get label => switch (this) {
    CardType.basic => 'Basic',
    CardType.reversed => 'Reversed',
    CardType.cloze => 'Cloze deletion',
  };

  String get description => switch (this) {
    CardType.basic => 'Front shows the question, back shows the answer.',
    CardType.reversed =>
      'Creates two cards with independent schedules: front→back and '
          'back→front.',
    CardType.cloze =>
      'Every {{c1::...}} deletion becomes a separately scheduled card.',
  };

  static CardType fromIndex(int? index) {
    if (index == null || index < 0 || index >= CardType.values.length) {
      return CardType.basic;
    }
    return CardType.values[index];
  }
}

/// Learning state of a card. Values intentionally match the FSRS `State`
/// values (1 = learning, 2 = review, 3 = relearning); 0 is a brand new card.
enum CardLearningState {
  newCard,
  learning,
  review,
  relearning;

  String get label => switch (this) {
    CardLearningState.newCard => 'New',
    CardLearningState.learning => 'Learning',
    CardLearningState.review => 'Review',
    CardLearningState.relearning => 'Relearning',
  };

  static CardLearningState fromIndex(int? index) {
    if (index == null ||
        index < 0 ||
        index >= CardLearningState.values.length) {
      return CardLearningState.newCard;
    }
    return CardLearningState.values[index];
  }
}

final RegExp _clozePattern = RegExp(
  r'\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}',
  dotAll: true,
);

/// A single flashcard.
///
/// Fields 0-3 are the original persisted schema. Everything else was added
/// later; the Hive adapter supplies safe defaults for old records so existing
/// user data keeps working after upgrading.
@HiveType(typeId: 0)
class CardItem {
  @HiveField(0)
  final String frontText;

  @HiveField(1)
  final String backText;

  @HiveField(2)
  final String collectionId;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  final String id;

  @HiveField(5)
  final CardType type;

  @HiveField(6)
  final List<String> tags;

  @HiveField(7)
  final CardLearningState state;

  @HiveField(8)
  final int? step;

  @HiveField(9)
  final double? stability;

  @HiveField(10)
  final double? difficulty;

  @HiveField(11)
  final DateTime? due;

  @HiveField(12)
  final DateTime? lastReview;

  @HiveField(13)
  final int reps;

  @HiveField(14)
  final int lapses;

  @HiveField(15)
  final DateTime updatedAt;

  @HiveField(16)
  final String? imagePath;

  @HiveField(17)
  final String? audioPath;

  /// Groups sibling cards generated from the same note. Falls back to [id] when
  /// null (legacy records).
  @HiveField(18)
  final String? noteId;

  /// Direction for two-sided cards: false = front→back, true = back→front.
  @HiveField(19)
  final bool reverse;

  /// 1-based cloze deletion number for cloze cards (0 when not applicable).
  @HiveField(20)
  final int clozeIndex;

  CardItem({
    required this.frontText,
    required this.backText,
    required this.collectionId,
    DateTime? createdAt,
    String? id,
    this.type = CardType.basic,
    this.tags = const [],
    this.state = CardLearningState.newCard,
    this.step,
    this.stability,
    this.difficulty,
    this.due,
    this.lastReview,
    this.reps = 0,
    this.lapses = 0,
    DateTime? updatedAt,
    this.imagePath,
    this.audioPath,
    this.noteId,
    this.reverse = false,
    this.clozeIndex = 0,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       id = id ?? newId();

  static const Object _unset = Object();

  String get noteKey => noteId ?? id;

  bool get isCloze => type == CardType.cloze;

  bool get isReverseSibling => reverse;

  /// Human label for the sibling variant, shown in previews and browsers.
  String? get variantLabel {
    if (isCloze) return 'Cloze $clozeIndex';
    if (reverse) return 'Reverse';
    return null;
  }

  /// Unique, sorted cloze deletion numbers in this note.
  List<int> get clozeNumbers {
    final numbers = <int>{};
    for (final match in _clozePattern.allMatches(frontText)) {
      final value = int.tryParse(match.group(1) ?? '');
      if (value != null && value > 0) numbers.add(value);
    }
    final sorted = numbers.toList()..sort();
    return sorted;
  }

  bool get isNew => state == CardLearningState.newCard;
  bool get isLearning => state == CardLearningState.learning;
  bool get isReview => state == CardLearningState.review;
  bool get isRelearning => state == CardLearningState.relearning;

  /// True when the card is waiting to be studied at [now].
  bool isDue({DateTime? now}) {
    final current = now ?? DateTime.now();
    if (isNew) return true;
    final dueDate = due;
    if (dueDate == null) return true;
    return !dueDate.isAfter(current);
  }

  /// Study queue order: learning cards first, then due reviews, then new.
  int get queuePriority => switch (state) {
    CardLearningState.learning || CardLearningState.relearning => 0,
    CardLearningState.review => 1,
    CardLearningState.newCard => 2,
  };

  double get retrievability {
    if (stability == null || lastReview == null || stability! <= 0) return 0;
    final elapsed = math.max(0, DateTime.now().difference(lastReview!).inDays);
    final factor = math.pow(0.9, 1 / -0.5) - 1;
    return math.pow(1 + factor * elapsed / stability!, -0.5).toDouble();
  }

  /// Text shown on the question side of this specific card.
  String get studyFront {
    if (isCloze) return clozeFrontText;
    return reverse ? backText : frontText;
  }

  /// Text shown on the answer side of this specific card.
  String get studyBack {
    if (isCloze) return clozeBackText;
    return reverse ? frontText : backText;
  }

  /// The note text with only this card's cloze deletion hidden; other
  /// deletions stay visible so each sibling is independently reviewable.
  String get clozeFrontText {
    final active = clozeIndex;
    return frontText.replaceAllMapped(_clozePattern, (match) {
      final index = int.tryParse(match.group(1) ?? '') ?? 0;
      if (active <= 0 || index == active) {
        final hint = match.group(3)?.trim();
        return hint == null || hint.isEmpty ? '[...]' : '[$hint]';
      }
      return match.group(2) ?? '';
    });
  }

  /// The full note with the active deletion highlighted.
  String get clozeBackText {
    final active = clozeIndex;
    final revealed = frontText.replaceAllMapped(_clozePattern, (match) {
      final index = int.tryParse(match.group(1) ?? '') ?? 0;
      final answer = match.group(2) ?? '';
      if (active <= 0 || index == active) return '==$answer==';
      return answer;
    });
    final extra = backText.trim();
    return extra.isEmpty ? revealed : '$revealed\n\n$extra';
  }

  bool get hasCloze => _clozePattern.hasMatch(frontText);

  bool get isPlayable => audioPath != null && audioPath!.trim().isNotEmpty;

  bool get hasImage => imagePath != null && imagePath!.trim().isNotEmpty;

  /// Returns a validation error message, or null when the card is valid.
  String? validate() {
    final l10n = AppLocalizations.current;
    if (frontText.trim().isEmpty) return l10n.frontCannotBeEmpty;
    if (type == CardType.cloze) {
      if (!hasCloze) {
        return l10n.clozeNeedsDeletion;
      }
      return null;
    }
    if (backText.trim().isEmpty) return l10n.backCannotBeEmpty;
    return null;
  }

  CardItem copyWith({
    String? frontText,
    String? backText,
    String? collectionId,
    DateTime? createdAt,
    String? id,
    CardType? type,
    List<String>? tags,
    CardLearningState? state,
    Object? step = _unset,
    Object? stability = _unset,
    Object? difficulty = _unset,
    Object? due = _unset,
    Object? lastReview = _unset,
    int? reps,
    int? lapses,
    DateTime? updatedAt,
    Object? imagePath = _unset,
    Object? audioPath = _unset,
    Object? noteId = _unset,
    bool? reverse,
    int? clozeIndex,
  }) {
    return CardItem(
      frontText: frontText ?? this.frontText,
      backText: backText ?? this.backText,
      collectionId: collectionId ?? this.collectionId,
      createdAt: createdAt ?? this.createdAt,
      id: id ?? this.id,
      type: type ?? this.type,
      tags: tags ?? this.tags,
      state: state ?? this.state,
      step: identical(step, _unset) ? this.step : step as int?,
      stability: identical(stability, _unset)
          ? this.stability
          : stability as double?,
      difficulty: identical(difficulty, _unset)
          ? this.difficulty
          : difficulty as double?,
      due: identical(due, _unset) ? this.due : due as DateTime?,
      lastReview: identical(lastReview, _unset)
          ? this.lastReview
          : lastReview as DateTime?,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
      updatedAt: updatedAt ?? DateTime.now(),
      imagePath: identical(imagePath, _unset)
          ? this.imagePath
          : imagePath as String?,
      audioPath: identical(audioPath, _unset)
          ? this.audioPath
          : audioPath as String?,
      noteId: identical(noteId, _unset) ? this.noteId : noteId as String?,
      reverse: reverse ?? this.reverse,
      clozeIndex: clozeIndex ?? this.clozeIndex,
    );
  }

  /// Plain copy that keeps identity, used when duplicating into a new card.
  CardItem duplicate({
    String? collectionId,
    String? id,
    String? noteId,
    bool? reverse,
  }) => CardItem(
    frontText: frontText,
    backText: backText,
    collectionId: collectionId ?? this.collectionId,
    id: id,
    type: type,
    tags: List<String>.from(tags),
    imagePath: imagePath,
    audioPath: audioPath,
    noteId: noteId,
    reverse: reverse ?? this.reverse,
    clozeIndex: clozeIndex,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'frontText': frontText,
    'backText': backText,
    'collectionId': collectionId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'type': type.name,
    'tags': tags,
    'state': state.name,
    'step': step,
    'stability': stability,
    'difficulty': difficulty,
    'due': due?.toUtc().toIso8601String(),
    'lastReview': lastReview?.toUtc().toIso8601String(),
    'reps': reps,
    'lapses': lapses,
    'imagePath': imagePath,
    'audioPath': audioPath,
    'noteId': noteId,
    'reverse': reverse,
    'clozeIndex': clozeIndex,
  };

  factory CardItem.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String?;
    final stateName = json['state'] as String?;
    return CardItem(
      id: json['id'] as String?,
      frontText: json['frontText'] as String? ?? '',
      backText: json['backText'] as String? ?? '',
      collectionId: json['collectionId'] as String? ?? '',
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt']) ?? DateTime.now(),
      type: CardType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () => CardType.basic,
      ),
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
      state: CardLearningState.values.firstWhere(
        (value) => value.name == stateName,
        orElse: () => CardLearningState.newCard,
      ),
      step: (json['step'] as num?)?.toInt(),
      stability: (json['stability'] as num?)?.toDouble(),
      difficulty: (json['difficulty'] as num?)?.toDouble(),
      due: _parseDate(json['due']),
      lastReview: _parseDate(json['lastReview']),
      reps: (json['reps'] as num?)?.toInt() ?? 0,
      lapses: (json['lapses'] as num?)?.toInt() ?? 0,
      imagePath: json['imagePath'] as String?,
      audioPath: json['audioPath'] as String?,
      noteId: json['noteId'] as String?,
      reverse: json['reverse'] as bool? ?? false,
      clozeIndex: (json['clozeIndex'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CardItem && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'CardItem(id: $id, type: ${type.name}, state: ${state.name}, '
      'reps: $reps, due: $due)';
}
