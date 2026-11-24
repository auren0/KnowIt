import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/screens/create_collection_screen.dart';
import 'package:knowit/screens/study_screen.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/tabs/cards_tab.dart';
import 'package:knowit/tabs/overview_tab.dart';
import 'package:knowit/tabs/stats_tab.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/deck_tree.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/app_emoji.dart';
import 'package:knowit/widgets/empty_state.dart';
import 'package:knowit/widgets/study_mode_sheet.dart';

enum CollectionTab { overview, cards, stats }

class CollectionScreen extends StatefulWidget {
  final String collectionId;
  final String name;
  final String emoji;
  final Color color;
  final int cardCount;
  final double progress;
  final DateTime createdAt;

  const CollectionScreen({
    super.key,
    required this.collectionId,
    required this.name,
    required this.emoji,
    required this.color,
    required this.cardCount,
    required this.progress,
    required this.createdAt,
  });

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  CollectionTab _tab = CollectionTab.overview;

  Future<void> _study(Collection deck) async {
    final mode = await showStudyModeSheet(context, deckName: deck.name);
    if (mode == null || !mounted) return;
    final collections = HiveService.getAllCollections();
    final ids = <String>[deck.id, ...descendantDeckIds(collections, deck.id)];
    await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => StudyScreen(deckIds: ids, title: deck.name, mode: mode),
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

  Future<void> _addSubdeck(Collection deck) async {
    await Navigator.push<Collection>(
      context,
      CupertinoPageRoute(
        builder: (_) => CreateCollectionScreen(parentId: deck.id),
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
    final subdeckCount = descendantDeckIds(
      HiveService.getAllCollections(),
      deck.id,
    ).length;
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
    if (!confirmed) return;
    final snapshot = await HiveService.deleteCollectionCascade(deck.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    if (snapshot == null) return;
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.deleted(deck.name)),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => HiveService.restoreDeckSnapshot(snapshot),
        ),
      ),
    );
    controller.closed.then((reason) {
      if (reason != SnackBarClosedReason.action) {
        HiveService.cleanupOrphanedMedia();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final onColor = theme.colorScheme.onPrimaryContainer;

    return AnimatedBuilder(
      animation: HiveService.collectionsListenable,
      builder: (context, _) {
        final deck = HiveService.getCollection(widget.collectionId);
        if (deck == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: AppIcons.folderMissing,
              title: l10n.collectionNotFound,
              message: l10n.collectionDeleted,
              action: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.goBack),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: theme.colorScheme.primaryContainer,
            title: Row(
              children: [
                AppEmoji(deck.emoji, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    deck.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: onColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: l10n.studyCollectionTooltip(deck.name),
                onPressed: () => _study(deck),
                icon: const Icon(AppIcons.playCircle),
              ),
              PopupMenuButton<String>(
                tooltip: l10n.collectionOptions,
                icon: const Icon(AppIcons.more),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _edit(deck);
                    case 'subdeck':
                      _addSubdeck(deck);
                    case 'duplicate':
                      _duplicate(deck);
                    case 'delete':
                      _delete(deck);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(AppIcons.edit),
                      title: Text(l10n.editCollection),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'subdeck',
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(AppIcons.folderAdd),
                      title: Text(l10n.addSubcollection),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'duplicate',
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(AppIcons.copy),
                      title: Text(l10n.duplicate),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(AppIcons.delete),
                      title: Text(l10n.delete),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SegmentedButton<CollectionTab>(
                    segments: [
                      ButtonSegment(
                        value: CollectionTab.overview,
                        icon: const Icon(AppIcons.bookOpen, size: 18),
                        label: Text(l10n.overview),
                      ),
                      ButtonSegment(
                        value: CollectionTab.cards,
                        icon: const Icon(AppIcons.card, size: 18),
                        label: Text(l10n.cards),
                      ),
                      ButtonSegment(
                        value: CollectionTab.stats,
                        icon: const Icon(AppIcons.statistics, size: 18),
                        label: Text(l10n.stats),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (value) {
                      setState(() => _tab = value.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: KeyedSubtree(
                        key: ValueKey(_tab),
                        child: _buildContent(deck),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(Collection deck) {
    switch (_tab) {
      case CollectionTab.overview:
        return OverviewTab(collectionId: deck.id);
      case CollectionTab.cards:
        return CardsTab(collectionId: deck.id);
      case CollectionTab.stats:
        return StatsTab(collectionId: deck.id);
    }
  }
}
