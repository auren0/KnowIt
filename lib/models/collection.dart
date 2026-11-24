import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:knowit/utils/id_generator.dart';

part 'collection.g.dart';

/// A deck (called "collection" in the original KnowIt UI).
///
/// Fields 0-6 are the original schema. [parentId] and [description] were added
/// later; the Hive adapter is backwards compatible with old records.
@HiveType(typeId: 1)
class Collection {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String emoji;

  @HiveField(3)
  final int colorValue;

  @HiveField(4)
  final int cardCount;

  @HiveField(5)
  final double progress;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  final String? parentId;

  @HiveField(8)
  final String description;

  @HiveField(9)
  final DateTime updatedAt;

  @HiveField(10)
  final int sortOrder;

  Collection({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorValue,
    this.cardCount = 0,
    this.progress = 0.0,
    DateTime? createdAt,
    this.parentId,
    this.description = '',
    DateTime? updatedAt,
    this.sortOrder = 0,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory Collection.fromColor({
    required String id,
    required String name,
    required String emoji,
    required Color color,
    int cardCount = 0,
    double progress = 0.0,
    DateTime? createdAt,
    String? parentId,
    String description = '',
    int sortOrder = 0,
  }) {
    return Collection(
      id: id,
      name: name,
      emoji: emoji,
      colorValue: color.toARGB32(),
      cardCount: cardCount,
      progress: progress,
      createdAt: createdAt,
      parentId: parentId,
      description: description,
      sortOrder: sortOrder,
    );
  }

  Color get color => Color(colorValue);

  bool get isSubdeck => parentId != null && parentId!.isNotEmpty;

  factory Collection.create({
    required String name,
    required String emoji,
    required Color color,
    String? parentId,
    String description = '',
    int sortOrder = 0,
  }) {
    return Collection.fromColor(
      id: newId(),
      name: name,
      emoji: emoji,
      color: color,
      parentId: parentId,
      description: description,
      sortOrder: sortOrder,
    );
  }

  static const Object _unset = Object();

  Collection copyWith({
    String? id,
    String? name,
    String? emoji,
    Color? color,
    int? cardCount,
    double? progress,
    DateTime? createdAt,
    Object? parentId = _unset,
    String? description,
    DateTime? updatedAt,
    int? sortOrder,
  }) {
    return Collection(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      colorValue: color?.toARGB32() ?? colorValue,
      cardCount: cardCount ?? this.cardCount,
      progress: progress ?? this.progress,
      createdAt: createdAt ?? this.createdAt,
      parentId: identical(parentId, _unset)
          ? this.parentId
          : parentId as String?,
      description: description ?? this.description,
      updatedAt: updatedAt ?? DateTime.now(),
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'colorValue': colorValue,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'parentId': parentId,
    'description': description,
    'sortOrder': sortOrder,
  };

  factory Collection.fromJson(Map<String, dynamic> json) {
    return Collection(
      id: json['id'] as String? ?? newId(),
      name: json['name'] as String? ?? 'Untitled deck',
      emoji: json['emoji'] as String? ?? '',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFFFFC107,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      parentId: json['parentId'] as String?,
      description: json['description'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Collection && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Collection{id: $id, name: $name, emoji: $emoji, cardCount: $cardCount}';
}
