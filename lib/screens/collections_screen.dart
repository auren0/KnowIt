import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/screens/collection_screen.dart';
import 'package:knowit/screens/create_card_screen.dart';
import 'package:knowit/screens/create_collection_screen.dart';
import 'package:knowit/screens/study_screen.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/settings_service.dart';
import 'package:knowit/services/stats_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/deck_tree.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/collection_card.dart';
import 'package:knowit/widgets/empty_state.dart';
import 'package:knowit/widgets/insights.dart';
import 'package:knowit/widgets/study_mode_sheet.dart';

enum DeckSort { manual, name, newest, due, cards }

enum DeckFilter { all, due, hasNew, empty }

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  static const StatsService _stats = StatsService();
  final TextEditingController _searchController = TextEditingController();
  DeckSort _sort = DeckSort.manual;
  DeckFilter _filter = DeckFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, DeckMetrics> _metricsFor(
    List<Collection> collections,
    List<CardItem> cards,
  ) {
    final result = <String, DeckMetrics>{};
    for (final deck in collections) {
      final ids = descendantDeckIds(collections, deck.id)..add(deck.id);
      result[deck.id] = _stats.deckMetrics(
        cards.where((card) => ids.contains(card.collectionId)).toList(),
      );
    }
    return result;
  }

  Future<void> _openDeck(Collection deck) async {
    await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => CollectionScreen(
          collectionId: deck.id,
          name: deck.name,
          emoji: deck.emoji,
          color: deck.color,
          cardCount: deck.cardCount,
          progress: deck.progress,
          createdAt: deck.createdAt,
        ),
      ),
    );
  }

  Future<void> _study(Collection deck, {StudyMode? mode}) async {
    final collections = HiveService.getAllCollections();
    final ids = <String>[deck.id, ...descendantDeckIds(collections, deck.id)];
    final cards = HiveService.getCardsForCollections(ids);
    if (cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.collectionHasNoCards(deck.name))),
      );
      return;
    }
    final selectedMode =
        mode ?? await showStudyModeSheet(context, deckName: deck.name);
    if (selectedMode == null || !mounted) return;
    await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) =>
            StudyScreen(deckIds: ids, title: deck.name, mode: selectedMode),
      ),
    );
  }

  Future<void> _studyAll() async {
    final cards = HiveService.getAllCards();
    if (cards.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.addCardsFirst)));
      return;
    }
    final collections = HiveService.getAllCollections();
    await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => StudyScreen(
          deckIds: collections.map((deck) => deck.id).toList(),
          title: context.l10n.allCollections,
          mode: StudyMode.srs,
        ),
      ),
    );
  }

  Future<void> _create({String? parentId}) async {
    await Navigator.push<Collection>(
      context,
      CupertinoPageRoute(
        builder: (_) => CreateCollectionScreen(parentId: parentId),
      ),
    );
  }

  Future<void> _edit(Collection deck) async {
    await Navigator.push<Collection>(
      context,
      CupertinoPageRoute(
        builder: (_) => CreateCollectionScreen(collection: deck),
      ),
    );
  }

  Future<void> _duplicate(Collection deck) async {
    final copies = await HiveService.duplicateCollection(deck.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copies.isEmpty
              ? context.l10n.couldNotDuplicate
              : context.l10n.duplicated(deck.name),
        ),
      ),
    );
  }

  Future<void> _delete(Collection deck) async {
    final l10n = context.l10n;
    final collections = HiveService.getAllCollections();
    final subdeckCount = descendantDeckIds(collections, deck.id).length;
    final cardCount = HiveService.getCardsByCollection(deck.id).length;
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.deleteCollectionTitle(deck.name),
      message: l10n.deleteCollectionBody(
        l10n.cardPart(cardCount),
        l10n.subdeckPart(subdeckCount),
      ),
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (confirmed != true) return;
    final snapshot = await HiveService.deleteCollectionCascade(deck.id);
    if (!mounted || snapshot == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            content: Text(l10n.deleted(deck.name)),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: l10n.undo,
              onPressed: () => HiveService.restoreDeckSnapshot(snapshot),
            ),
          ),
        )
        .closed
        .then((reason) {
          if (reason != SnackBarClosedReason.action) {
            HiveService.cleanupOrphanedMedia();
          }
        });
  }

  Future<void> _handleSuggestion(StudySuggestion suggestion) async {
    if (HiveService.getAllCollections().isEmpty) {
      await _create();
      return;
    }
    final collections = HiveService.getAllCollections();
    final deckId = suggestion.deckId;
    final targetDeck = deckId == null
        ? null
        : HiveService.getCollection(deckId);
    final ids = targetDeck == null
        ? collections.map((deck) => deck.id).toList()
        : <String>[
            targetDeck.id,
            ...descendantDeckIds(collections, targetDeck.id),
          ];
    final cards = HiveService.getCardsForCollections(ids);
    if (cards.isEmpty) {
      final firstDeck = targetDeck ?? collections.first;
      final result = await Navigator.push<CardEditorResult>(
        context,
        CupertinoPageRoute(
          builder: (_) => CreateCardScreen(collectionId: firstDeck.id),
        ),
      );
      if (!mounted || result?.card == null) return;
      return;
    }
    final mode = suggestion.actionLabel == context.l10n.practice
        ? StudyMode.difficult
        : StudyMode.srs;
    await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => StudyScreen(
          deckIds: ids,
          title: targetDeck?.name ?? context.l10n.allCollections,
          mode: mode,
        ),
      ),
    );
  }

  List<DeckTreeNode> _sortedForest(
    List<Collection> collections,
    Map<String, DeckMetrics> metrics,
  ) {
    final forest = buildDeckForest(collections);

    int compare(DeckTreeNode a, DeckTreeNode b) {
      final aMetrics = metrics[a.deck.id] ?? DeckMetrics.empty;
      final bMetrics = metrics[b.deck.id] ?? DeckMetrics.empty;
      switch (_sort) {
        case DeckSort.manual:
          final order = a.deck.sortOrder.compareTo(b.deck.sortOrder);
          return order != 0
              ? order
              : a.deck.createdAt.compareTo(b.deck.createdAt);
        case DeckSort.name:
          return a.deck.name.toLowerCase().compareTo(b.deck.name.toLowerCase());
        case DeckSort.newest:
          return b.deck.createdAt.compareTo(a.deck.createdAt);
        case DeckSort.due:
          return (bMetrics.due + bMetrics.newCards).compareTo(
            aMetrics.due + aMetrics.newCards,
          );
        case DeckSort.cards:
          return bMetrics.total.compareTo(aMetrics.total);
      }
    }

    void sortNodes(List<DeckTreeNode> nodes) {
      nodes.sort(compare);
      for (final node in nodes) {
        sortNodes(node.children);
      }
    }

    sortNodes(forest);
    return flattenDeckForest(forest);
  }

  bool _matchesFilter(DeckMetrics metrics) => switch (_filter) {
    DeckFilter.all => true,
    DeckFilter.due => metrics.due > 0,
    DeckFilter.hasNew => metrics.newCards > 0,
    DeckFilter.empty => metrics.total == 0,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedBuilder(
      animation: Listenable.merge([
        HiveService.collectionsListenable,
        HiveService.cardsListenable,
        HiveService.logsListenable,
      ]),
      builder: (context, _) {
        final collections = HiveService.getAllCollections();
        final cards = HiveService.getAllCards();
        final metrics = _metricsFor(collections, cards);
        final query = _searchController.text.trim().toLowerCase();
        final flatNodes = _sortedForest(collections, metrics).where((node) {
          if (!_matchesFilter(metrics[node.deck.id] ?? DeckMetrics.empty)) {
            return false;
          }
          if (query.isEmpty) return true;
          return node.deck.name.toLowerCase().contains(query) ||
              node.deck.description.toLowerCase().contains(query) ||
              deckBreadcrumb(
                collections,
                node.deck,
              ).toLowerCase().contains(query);
        }).toList();
        final stats = _stats.learningStats(
          logs: HiveService.getAllLogs(),
          cards: cards,
        );
        final suggestions = _stats.suggestions(
          collections: collections,
          cards: cards,
          logs: HiveService.getAllLogs(),
          settings: SettingsService.value,
        );
        final dueTotal = cards.where((card) => card.isDue()).length;
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.collections),
            actions: [
              if (dueTotal > 0)
                IconButton(
                  tooltip: l10n.studyAllDue,
                  onPressed: _studyAll,
                  icon: const Icon(AppIcons.playCircle),
                ),
              PopupMenuButton<DeckSort>(
                tooltip: l10n.sortCollections,
                icon: const Icon(AppIcons.sort),
                onSelected: (value) => setState(() => _sort = value),
                itemBuilder: (context) => [
                  for (final sort in DeckSort.values)
                    CheckedPopupMenuItem(
                      value: sort,
                      checked: _sort == sort,
                      child: Text(_sortLabel(l10n, sort)),
                    ),
                ],
              ),
              PopupMenuButton<DeckFilter>(
                tooltip: l10n.filterCollections,
                icon: Icon(
                  AppIcons.filter,
                  color: _filter == DeckFilter.all
                      ? null
                      : theme.colorScheme.primary,
                ),
                onSelected: (value) => setState(() => _filter = value),
                itemBuilder: (context) => [
                  for (final filter in DeckFilter.values)
                    CheckedPopupMenuItem(
                      value: filter,
                      checked: _filter == filter,
                      child: Text(_filterLabel(l10n, filter)),
                    ),
                ],
              ),
            ],
          ),
          body: collections.isEmpty
              ? EmptyState(
                  icon: AppIcons.collectionsSelected,
                  title: l10n.noCollectionsTitle,
                  message: l10n.noCollectionsMessage,
                  action: FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(AppIcons.add),
                    label: Text(l10n.newCollection),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: l10n.searchCollections,
                          prefixIcon: const Icon(AppIcons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  tooltip: l10n.clearSearch,
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(AppIcons.clear),
                                )
                              : null,
                        ),
                      ),
                    ),
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (query.isEmpty &&
                                      _filter == DeckFilter.all &&
                                      suggestions.isNotEmpty) ...[
                                    SuggestionCard(
                                      suggestion: suggestions.first,
                                      onAction: () =>
                                          _handleSuggestion(suggestions.first),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  Row(
                                    children: [
                                      Text(
                                        l10n.shownOfTotal(
                                          flatNodes.length,
                                          collections.length,
                                        ),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                      const Spacer(),
                                      if (stats.currentStreak > 0)
                                        StatePill(
                                          label: l10n.dayStreakShort(
                                            stats.currentStreak,
                                          ),
                                          color: theme.colorScheme.primary,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (flatNodes.isEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverToBoxAdapter(
                                child: EmptyState(
                                  icon: AppIcons.search,
                                  title: l10n.noMatchingCollections,
                                  message: l10n.noMatchingCollectionsMessage,
                                  action: TextButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _filter = DeckFilter.all;
                                        _sort = DeckSort.manual;
                                      });
                                    },
                                    child: Text(l10n.resetSearchAndFilters),
                                  ),
                                  compact: true,
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              sliver: SliverList.builder(
                                itemCount: flatNodes.length,
                                itemBuilder: (context, index) {
                                  final node = flatNodes[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: DeckCard(
                                      collection: node.deck,
                                      metrics:
                                          metrics[node.deck.id] ??
                                          DeckMetrics.empty,
                                      depth: node.depth,
                                      onTap: () => _openDeck(node.deck),
                                      onStudy: () => _study(node.deck),
                                      onEdit: () => _edit(node.deck),
                                      onDuplicate: () => _duplicate(node.deck),
                                      onAddSubdeck: () =>
                                          _create(parentId: node.deck.id),
                                      onDelete: () => _delete(node.deck),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
          floatingActionButton: collections.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: _create,
                  label: Text(l10n.newCollection),
                  icon: const Icon(AppIcons.add),
                ),
        );
      },
    );
  }

  static String _sortLabel(AppLocalizations l10n, DeckSort sort) =>
      switch (sort) {
        DeckSort.manual => l10n.manualOrder,
        DeckSort.name => l10n.nameAZ,
        DeckSort.newest => l10n.newestFirst,
        DeckSort.due => l10n.mostDue,
        DeckSort.cards => l10n.mostCards,
      };

  static String _filterLabel(AppLocalizations l10n, DeckFilter filter) =>
      switch (filter) {
        DeckFilter.all => l10n.allCollectionsFilter,
        DeckFilter.due => l10n.withCardsDue,
        DeckFilter.hasNew => l10n.withNewCards,
        DeckFilter.empty => l10n.emptyCollections,
      };
}
