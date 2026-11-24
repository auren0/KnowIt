import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/sync/tombstone_store.dart';

export 'tombstone_store.dart';

/// Portable local sync payload. No network transport or backend is configured;
/// this is the foundation a future sync provider can use.
class SyncPayload {
  final List<Collection> collections;
  final List<CardItem> cards;
  final List<ReviewLog> logs;
  final List<SyncTombstone> tombstones;

  const SyncPayload({
    this.collections = const [],
    this.cards = const [],
    this.logs = const [],
    this.tombstones = const [],
  });

  Map<String, dynamic> toJson() => {
    'format': 'knowit-sync',
    'version': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'collections': collections.map((deck) => deck.toJson()).toList(),
    'cards': cards.map((card) => card.toJson()).toList(),
    'logs': logs.map((log) => log.toJson()).toList(),
    'tombstones': tombstones.map((item) => item.toJson()).toList(),
  };

  factory SyncPayload.fromJson(Map<String, dynamic> json) {
    if (json['format'] != null && json['format'] != 'knowit-sync') {
      throw const FormatException('This is not a KnowIt sync payload.');
    }
    final collections = <Collection>[];
    final rawCollections = json['collections'];
    if (rawCollections is List) {
      for (final item in rawCollections) {
        if (item is Map<String, dynamic>) {
          try {
            collections.add(Collection.fromJson(item));
          } on Object {
            // Ignore one malformed record instead of discarding the payload.
          }
        }
      }
    }
    final cards = <CardItem>[];
    final rawCards = json['cards'];
    if (rawCards is List) {
      for (final item in rawCards) {
        if (item is Map<String, dynamic>) {
          try {
            final card = CardItem.fromJson(item);
            if (card.frontText.trim().isNotEmpty) cards.add(card);
          } on Object {
            // Ignore one malformed card.
          }
        }
      }
    }
    final logs = <ReviewLog>[];
    final rawLogs = json['logs'];
    if (rawLogs is List) {
      for (final item in rawLogs) {
        if (item is Map<String, dynamic>) {
          try {
            logs.add(ReviewLog.fromJson(item));
          } on Object {
            // Ignore one malformed log.
          }
        }
      }
    }
    final tombstones = <SyncTombstone>[];
    final rawTombstones = json['tombstones'];
    if (rawTombstones is List) {
      for (final item in rawTombstones) {
        if (item is Map<String, dynamic>) {
          try {
            tombstones.add(SyncTombstone.fromJson(item));
          } on Object {
            // Ignore one malformed tombstone.
          }
        }
      }
    }
    return SyncPayload(
      collections: collections,
      cards: cards,
      logs: logs,
      tombstones: tombstones,
    );
  }
}

class SyncMergePlan {
  final List<Collection> collectionsToSave;
  final List<CardItem> cardsToSave;
  final List<ReviewLog> logsToAdd;
  final List<String> collectionIdsToDelete;
  final List<String> cardIdsToDelete;
  final List<SyncTombstone> tombstonesToStore;
  final List<SyncTombstone> tombstonesToRemove;
  final List<String> conflicts;

  const SyncMergePlan({
    this.collectionsToSave = const [],
    this.cardsToSave = const [],
    this.logsToAdd = const [],
    this.collectionIdsToDelete = const [],
    this.cardIdsToDelete = const [],
    this.tombstonesToStore = const [],
    this.tombstonesToRemove = const [],
    this.conflicts = const [],
  });

  bool get isEmpty =>
      collectionsToSave.isEmpty &&
      cardsToSave.isEmpty &&
      logsToAdd.isEmpty &&
      collectionIdsToDelete.isEmpty &&
      cardIdsToDelete.isEmpty &&
      tombstonesToStore.isEmpty &&
      tombstonesToRemove.isEmpty;
}

class SyncMergeResult {
  final int collectionsSaved;
  final int cardsSaved;
  final int logsAdded;
  final int deleted;
  final int conflicts;

  const SyncMergeResult({
    required this.collectionsSaved,
    required this.cardsSaved,
    required this.logsAdded,
    required this.deleted,
    required this.conflicts,
  });

  String get summary =>
      '$collectionsSaved collections · $cardsSaved cards · '
      '$logsAdded reviews · $deleted deletions'
      '${conflicts > 0 ? ' · $conflicts conflicts kept local' : ''}';
}

/// Local-only synchronization engine.
///
/// - IDs are stable and operations are idempotent by id.
/// - Review logs are an append-only union, so merging can never erase study
///   history.
/// - Card conflicts never replace a locally more-reviewed card with a remote
///   record that has fewer repetitions; those are reported as conflicts.
/// - Tombstones prevent deleted records from resurrecting.
///
/// There is no cloud provider, authentication or transport here. Callers can
/// serialize [SyncPayload] and move it through any backend later.
class SyncService {
  const SyncService();

  SyncPayload exportPayload({DateTime? since}) {
    final threshold = since;
    return SyncPayload(
      collections: HiveService.getAllCollections()
          .where(
            (deck) => threshold == null || !deck.updatedAt.isBefore(threshold),
          )
          .toList(),
      cards: HiveService.getAllCards()
          .where(
            (card) => threshold == null || !card.updatedAt.isBefore(threshold),
          )
          .toList(),
      logs: HiveService.getAllLogs()
          .where(
            (log) => threshold == null || !log.reviewedAt.isBefore(threshold),
          )
          .toList(),
      tombstones: TombstoneStore.all(),
    );
  }

  SyncMergePlan planMerge(SyncPayload remote) {
    final localCollections = {
      for (final deck in HiveService.getAllCollections()) deck.id: deck,
    };
    final localCards = {
      for (final card in HiveService.getAllCards()) card.id: card,
    };
    final localLogs = {for (final log in HiveService.getAllLogs()) log.id: log};
    final localTombstones = {
      for (final item in TombstoneStore.all()) item.key: item,
    };
    final remoteTombstones = {
      for (final item in remote.tombstones) item.key: item,
    };

    final collectionsToSave = <Collection>[];
    final cardsToSave = <CardItem>[];
    final logsToAdd = <ReviewLog>[];
    final collectionIdsToDelete = <String>{};
    final cardIdsToDelete = <String>{};
    final tombstonesToStore = <SyncTombstone>[];
    final tombstonesToRemove = <SyncTombstone>[];
    final conflicts = <String>[];

    // Remote deletion wins only when it is at least as new as the local update.
    for (final tombstone in remoteTombstones.values) {
      if (tombstone.entityType == SyncEntityType.collection) {
        final local = localCollections[tombstone.entityId];
        if (local == null) {
          tombstonesToStore.add(tombstone);
          continue;
        }
        if (local.updatedAt.isAfter(tombstone.deletedAt)) {
          conflicts.add(
            'Collection ${local.name} changed after a remote deletion; '
            'kept local copy.',
          );
          continue;
        }
        collectionIdsToDelete.add(local.id);
        tombstonesToStore.add(tombstone);
        continue;
      }
      final local = localCards[tombstone.entityId];
      if (local == null) {
        tombstonesToStore.add(tombstone);
        continue;
      }
      if (local.updatedAt.isAfter(tombstone.deletedAt)) {
        conflicts.add(
          'A card was studied after a remote deletion; kept local review '
          'progress.',
        );
        continue;
      }
      cardIdsToDelete.add(local.id);
      tombstonesToStore.add(tombstone);
    }

    // Remote updates that are older than a local deletion must not resurrect.
    void acceptCollection(Collection deck) {
      final tombstone = localTombstones['collection:${deck.id}'];
      if (tombstone != null) {
        if (!deck.updatedAt.isAfter(tombstone.deletedAt)) return;
        tombstonesToRemove.add(tombstone);
        conflicts.add(
          'Collection ${deck.name} was re-created remotely after local '
          'deletion; accepted the newer record.',
        );
      }
      final local = localCollections[deck.id];
      if (local == null) {
        collectionsToSave.add(deck);
        return;
      }
      if (deck.updatedAt.isAfter(local.updatedAt)) {
        collectionsToSave.add(deck);
      } else if (deck.updatedAt.isAtSameMomentAs(local.updatedAt) &&
          deck.toJson().toString() != local.toJson().toString()) {
        conflicts.add('Collection ${deck.name} changed on both sides.');
      }
    }

    void acceptCard(CardItem card) {
      final tombstone = localTombstones['card:${card.id}'];
      if (tombstone != null) {
        if (!card.updatedAt.isAfter(tombstone.deletedAt)) return;
        tombstonesToRemove.add(tombstone);
        conflicts.add(
          'A card was re-created remotely after local deletion; accepted the '
          'newer record.',
        );
      }
      final local = localCards[card.id];
      if (local == null) {
        cardsToSave.add(card);
        return;
      }
      if (card.updatedAt.isAfter(local.updatedAt)) {
        if (card.reps < local.reps) {
          conflicts.add(
            'Remote card has newer metadata but fewer reviews than the local '
            'card; kept local scheduling.',
          );
          return;
        }
        cardsToSave.add(card);
      } else if (card.updatedAt.isAtSameMomentAs(local.updatedAt) &&
          card.toJson().toString() != local.toJson().toString()) {
        conflicts.add('A card changed on both sides at the same time.');
      }
    }

    for (final deck in remote.collections) {
      if (!collectionIdsToDelete.contains(deck.id)) acceptCollection(deck);
    }
    for (final card in remote.cards) {
      if (!cardIdsToDelete.contains(card.id)) acceptCard(card);
    }
    for (final log in remote.logs) {
      final local = localLogs[log.id];
      if (local == null) {
        logsToAdd.add(log);
      } else if (local.toJson().toString() != log.toJson().toString()) {
        conflicts.add('A review log differs by id; kept the local history.');
      }
    }

    return SyncMergePlan(
      collectionsToSave: collectionsToSave,
      cardsToSave: cardsToSave,
      logsToAdd: logsToAdd,
      collectionIdsToDelete: collectionIdsToDelete.toList(),
      cardIdsToDelete: cardIdsToDelete.toList(),
      tombstonesToStore: tombstonesToStore,
      tombstonesToRemove: tombstonesToRemove,
      conflicts: conflicts.toSet().toList(),
    );
  }

  Future<SyncMergeResult> applyPlan(SyncMergePlan plan) async {
    for (final deck in plan.collectionsToSave) {
      await HiveService.saveCollection(deck);
      await TombstoneStore.remove(SyncEntityType.collection, deck.id);
    }
    for (final card in plan.cardsToSave) {
      await HiveService.updateCard(card);
      await TombstoneStore.remove(SyncEntityType.card, card.id);
    }
    if (plan.logsToAdd.isNotEmpty) {
      await HiveService.addLogs(plan.logsToAdd);
    }
    for (final id in plan.collectionIdsToDelete) {
      await HiveService.deleteCollectionRecord(id);
    }
    if (plan.cardIdsToDelete.isNotEmpty) {
      await HiveService.deleteCards(plan.cardIdsToDelete);
    }
    for (final tombstone in plan.tombstonesToStore) {
      await TombstoneStore.add(
        tombstone.entityType,
        tombstone.entityId,
        at: tombstone.deletedAt,
      );
    }
    for (final tombstone in plan.tombstonesToRemove) {
      await TombstoneStore.remove(tombstone.entityType, tombstone.entityId);
    }
    await HiveService.refreshCardCounts();
    return SyncMergeResult(
      collectionsSaved: plan.collectionsToSave.length,
      cardsSaved: plan.cardsToSave.length,
      logsAdded: plan.logsToAdd.length,
      deleted: plan.collectionIdsToDelete.length + plan.cardIdsToDelete.length,
      conflicts: plan.conflicts.length,
    );
  }

  Future<SyncMergeResult> merge(SyncPayload remote) async {
    return applyPlan(planMerge(remote));
  }
}
