import 'package:hive/hive.dart';

enum SyncEntityType { collection, card }

class SyncTombstone {
  final SyncEntityType entityType;
  final String entityId;
  final DateTime deletedAt;

  const SyncTombstone({
    required this.entityType,
    required this.entityId,
    required this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
    'type': entityType.name,
    'id': entityId,
    'deletedAt': deletedAt.toUtc().toIso8601String(),
  };

  factory SyncTombstone.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String?;
    final type = SyncEntityType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => SyncEntityType.card,
    );
    final id = json['id'] as String? ?? '';
    final deletedAt =
        DateTime.tryParse(json['deletedAt'] as String? ?? '')?.toLocal() ??
        DateTime.now();
    if (id.isEmpty) {
      throw const FormatException('Tombstone has no entity id.');
    }
    return SyncTombstone(entityType: type, entityId: id, deletedAt: deletedAt);
  }

  String get key => '${entityType.name}:$entityId';
}

/// Durable deletion tombstones used by future sync transports. Local deletion
/// remains usable even when no transport is configured.
class TombstoneStore {
  static Box? _box;

  static Future<void> attach(Box box) async {
    _box = box;
  }

  static bool get isReady => _box != null;

  static List<SyncTombstone> all() {
    final box = _box;
    if (box == null) return const [];
    final result = <SyncTombstone>[];
    for (final value in box.values) {
      if (value is Map) {
        try {
          result.add(SyncTombstone.fromJson(Map<String, dynamic>.from(value)));
        } on Object {
          // Ignore one malformed tombstone rather than breaking sync state.
        }
      }
    }
    result.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return result;
  }

  static SyncTombstone? get(SyncEntityType type, String id) {
    final value = _box?.get('${type.name}:$id');
    if (value is! Map) return null;
    try {
      return SyncTombstone.fromJson(Map<String, dynamic>.from(value));
    } on Object {
      return null;
    }
  }

  static Future<void> add(
    SyncEntityType type,
    String id, {
    DateTime? at,
  }) async {
    final box = _box;
    if (box == null || id.isEmpty) return;
    final tombstone = SyncTombstone(
      entityType: type,
      entityId: id,
      deletedAt: at ?? DateTime.now(),
    );
    await box.put(tombstone.key, tombstone.toJson());
  }

  static Future<void> addAll(
    SyncEntityType type,
    Iterable<String> ids, {
    DateTime? at,
  }) async {
    final box = _box;
    if (box == null) return;
    final timestamp = at ?? DateTime.now();
    final entries = <String, Map<String, dynamic>>{};
    for (final id in ids) {
      if (id.isEmpty) continue;
      final tombstone = SyncTombstone(
        entityType: type,
        entityId: id,
        deletedAt: timestamp,
      );
      entries[tombstone.key] = tombstone.toJson();
    }
    if (entries.isNotEmpty) {
      await box.putAll(entries);
    }
  }

  static Future<void> remove(SyncEntityType type, String id) async {
    await _box?.delete('${type.name}:$id');
  }

  static Future<void> removeAll(
    SyncEntityType type,
    Iterable<String> ids,
  ) async {
    final box = _box;
    if (box == null) return;
    final keys = [for (final id in ids) if (id.isNotEmpty) '${type.name}:$id'];
    if (keys.isNotEmpty) {
      await box.deleteAll(keys);
    }
  }

  static Future<void> clear() async {
    await _box?.clear();
  }
}
