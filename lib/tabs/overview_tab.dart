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
import 'package:knowit/services/stats_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/deck_tree.dart';
import 'package:knowit/utils/formatters.dart';
import 'package:knowit/widgets/app_emoji.dart';
import 'package:knowit/widgets/empty_state.dart';
import 'package:knowit/widgets/grouped_list.dart';
import 'package:knowit/widgets/insights.dart';
import 'package:knowit/widgets/study_mode_sheet.dart';

class OverviewTab extends StatefulWidget {
  final String collectionId;

  const OverviewTab({super.key, required this.collectionId});

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  static const StatsService _stats = StatsService();

  Future<void> _openStudy(Collection deck, StudyMode mode) async {
    final collections = HiveService.getAllCollections();
    final ids = <String>[deck.id, ...descendantDeckIds(collections, deck.id)];
    await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => StudyScreen(deckIds: ids, title: deck.name, mode: mode),
      ),
    );
  }

  Future<void> _openModePicker(Collection deck) async {
    final mode = await showStudyModeSheet(context, deckName: deck.name);
    if (mode == null || !mounted) return;
    await _openStudy(deck, mode);
  }

  Future<void> _addCard(Collection deck) async {
    final result = await Navigator.push<CardEditorResult>(
      context,
      CupertinoPageRoute(
        builder: (_) => CreateCardScreen(collectionId: deck.id),
      ),
    );
    if (!mounted || result?.card == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${context.l10n.cardCreated} · ${deck.name}')),
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedBuilder(
      animation: Listenable.merge([
        HiveService.collectionsListenable,
        HiveService.cardsListenable,
      ]),
      builder: (context, _) {
        final deck = HiveService.getCollection(widget.collectionId);
        if (deck == null) {
          return EmptyState(
            icon: AppIcons.folderMissing,
            title: l10n.collectionNotFound,
            message: l10n.collectionDeleted,
            action: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.goBack),
            ),
          );
        }
        final cards = HiveService.getCardsByCollection(deck.id);
        final metrics = _stats.deckMetrics(cards);
        final collections = HiveService.getAllCollections();
        final subdecks =
            collections.where((item) => item.parentId == deck.id).toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
        final dueNow = metrics.due + metrics.newCards;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: deck.color.withValues(alpha: 0.10),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      ProgressRing(
                        value: metrics.progress,
                        size: 104,
                        color: deck.color,
                        caption: l10n.cardsStudied,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.cardCount(metrics.total),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                StatePill(
                                  label: l10n.newCards(metrics.newCards),
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                                StatePill(
                                  label: l10n.dueCards(metrics.due),
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                StatePill(
                                  label:
                                      '${metrics.learning} ${l10n.learning.toLowerCase()}',
                                  color: const Color(0xFFD08700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              metrics.nextDue == null
                                  ? metrics.total == 0
                                        ? l10n.firstCardPrompt
                                        : l10n.nothingScheduledCaughtUp
                                  : l10n.nextReviewLower(
                                      formatRelativeDue(
                                        metrics.nextDue!,
                                      ).toLowerCase(),
                                    ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (deck.description.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  deck.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: metrics.total == 0
                      ? null
                      : () => _openStudy(deck, StudyMode.srs),
                  icon: const Icon(AppIcons.play),
                  label: Text(
                    metrics.total == 0
                        ? l10n.addCardsToStartStudying
                        : dueNow > 0
                        ? l10n.studyNowReady(dueNow)
                        : l10n.studyNow,
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: deck.color,
                    foregroundColor: Colors.black.withValues(alpha: 0.82),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: metrics.total == 0
                          ? null
                          : () => _openModePicker(deck),
                      icon: const Icon(AppIcons.options, size: 18),
                      label: Text(l10n.moreModes),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addCard(deck),
                      icon: const Icon(AppIcons.add, size: 18),
                      label: Text(l10n.addCard),
                    ),
                  ),
                ],
              ),
              if (metrics.total == 0) ...[
                const SizedBox(height: 12),
                InfoBanner(icon: AppIcons.lightbulb, message: l10n.studyTip),
              ],
              const SizedBox(height: 24),
              SectionHeader(
                title: l10n.subcollections,
                subtitle: subdecks.isEmpty
                    ? l10n.subcollectionsEmptyHint
                    : l10n.includedWhenStudying(deck.name),
                trailing: TextButton.icon(
                  onPressed: () => _addSubdeck(deck),
                  icon: const Icon(AppIcons.add, size: 18),
                  label: Text(l10n.add),
                ),
              ),
              if (subdecks.isEmpty)
                Text(
                  l10n.noSubcollections,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                GroupedList(
                  children: [
                    for (final subdeck in subdecks)
                      _SubdeckTile(
                        deck: subdeck,
                        onTap: () {
                          Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => CollectionScreen(
                                collectionId: subdeck.id,
                                name: subdeck.name,
                                emoji: subdeck.emoji,
                                color: subdeck.color,
                                cardCount: subdeck.cardCount,
                                progress: subdeck.progress,
                                createdAt: subdeck.createdAt,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 24),
              SectionHeader(
                title: l10n.cards,
                subtitle: l10n.cardsSectionSubtitle,
                trailing: IconButton(
                  tooltip: l10n.addCard,
                  onPressed: () => _addCard(deck),
                  icon: const Icon(AppIcons.addCircle),
                ),
              ),
              if (cards.isNotEmpty)
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.latestCards,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        for (final card in _latestUniqueNotes(cards))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(
                                  card.hasCloze
                                      ? AppIcons.cloze
                                      : AppIcons.card,
                                  size: 16,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    card.studyFront.replaceAll('\n', ' '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

List<CardItem> _latestUniqueNotes(List<CardItem> cards) {
  final sorted = List<CardItem>.from(cards)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final seen = <String>{};
  final result = <CardItem>[];
  for (final card in sorted) {
    if (seen.add(card.noteKey)) result.add(card);
    if (result.length == 3) break;
  }
  return result;
}

class _SubdeckTile extends StatelessWidget {
  final Collection deck;
  final VoidCallback onTap;

  const _SubdeckTile({required this.deck, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final cards = HiveService.getCardsByCollection(
      deck.id,
      includeSubdecks: true,
    );
    final metrics = const StatsService().deckMetrics(cards);
    return ListTile(
      onTap: onTap,
      leading: AppEmoji(deck.emoji, size: 22),
      title: Text(
        deck.name,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${l10n.cardCount(metrics.total)}'
        '${metrics.due > 0 ? ' · ${l10n.dueCards(metrics.due)}' : ''}',
      ),
      trailing: const Icon(AppIcons.chevronRight),
    );
  }
}
