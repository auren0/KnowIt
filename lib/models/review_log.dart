import 'package:hive/hive.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/utils/id_generator.dart';

part 'review_log.g.dart';

/// Persistent record of a single card review.
///
/// Statistics are derived exclusively from these records, never from
/// hardcoded values. Practice modes are logged with their [mode] so they can be
/// excluded from retention calculations while still contributing to activity.
@HiveType(typeId: 2)
class ReviewLog {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String cardId;

  @HiveField(2)
  final String collectionId;

  /// FSRS rating: 1 = Again, 2 = Hard, 3 = Good, 4 = Easy.
  @HiveField(3)
  final int rating;

  @HiveField(4)
  final DateTime reviewedAt;

  @HiveField(5)
  final int durationMs;

  @HiveField(6)
  final String mode;

  @HiveField(7)
  final int previousState;

  @HiveField(8)
  final DateTime? previousDue;

  /// Scheduled interval in days after the rating (0 for sub-day learning steps).
  @HiveField(9)
  final int scheduledDays;

  ReviewLog({
    required this.cardId,
    required this.collectionId,
    required this.rating,
    required this.reviewedAt,
    String? id,
    this.durationMs = 0,
    this.mode = 'srs',
    this.previousState = 0,
    this.previousDue,
    this.scheduledDays = 0,
  }) : id = id ?? newId();

  StudyMode get studyMode => StudyMode.fromName(mode);

  bool get isScheduled => mode == StudyMode.srs.name;

  bool get wasCorrect => rating > 1;

  /// Number of days since the review, capped at 0.
  int daysAgo({DateTime? now}) {
    final current = now ?? DateTime.now();
    return current.difference(reviewedAt).inDays.clamp(0, 100000);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'cardId': cardId,
    'collectionId': collectionId,
    'rating': rating,
    'reviewedAt': reviewedAt.toUtc().toIso8601String(),
    'durationMs': durationMs,
    'mode': mode,
    'previousState': previousState,
    'previousDue': previousDue?.toUtc().toIso8601String(),
    'scheduledDays': scheduledDays,
  };

  factory ReviewLog.fromJson(Map<String, dynamic> json) {
    return ReviewLog(
      id: json['id'] as String?,
      cardId: json['cardId'] as String? ?? '',
      collectionId: json['collectionId'] as String? ?? '',
      rating: ((json['rating'] as num?)?.toInt() ?? 3).clamp(1, 4),
      reviewedAt:
          DateTime.tryParse(json['reviewedAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      mode: json['mode'] as String? ?? StudyMode.srs.name,
      previousState: (json['previousState'] as num?)?.toInt() ?? 0,
      previousDue: DateTime.tryParse(
        json['previousDue'] as String? ?? '',
      )?.toLocal(),
      scheduledDays: (json['scheduledDays'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ReviewLog && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
