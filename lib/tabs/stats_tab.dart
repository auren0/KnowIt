import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/screens/collection_screen.dart';
import 'package:knowit/screens/create_card_screen.dart';
import 'package:knowit/screens/study_screen.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/stats_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/formatters.dart';
import 'package:knowit/widgets/app_emoji.dart';
import 'package:knowit/widgets/empty_state.dart';
import 'package:knowit/widgets/grouped_list.dart';
import 'package:knowit/widgets/insights.dart';

class StatsTab extends StatelessWidget {
  final String? collectionId;

  const StatsTab({super.key, this.collectionId});

  static const StatsService _service = StatsService();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedBuilder(
      animation: Listenable.merge([
        HiveService.logsListenable,
        HiveService.cardsListenable,
        HiveService.collectionsListenable,
      ]),
      builder: (context, _) {
        final collections = HiveService.getAllCollections();
        final deck = collectionId == null
            ? null
            : HiveService.getCollection(collectionId!);
        final cards = collectionId == null
            ? HiveService.getAllCards()
            : HiveService.getCardsByCollection(collectionId!);
        final cardIds = cards.map((card) => card.id).toSet();
        final allLogs = HiveService.getAllLogs();
        final logs = collectionId == null
            ? allLogs
            : allLogs.where((log) => cardIds.contains(log.cardId)).toList();
        final stats = _service.learningStats(logs: logs, cards: cards);
        final theme = Theme.of(context);
        final deckMetrics = _service.deckMetrics(cards);

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (deck != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      AppEmoji(deck.emoji, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.statisticsFor(deck.name),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (stats.totalReviews == 0)
                Card(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          AppIcons.insights,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.realDataNotice,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      icon: AppIcons.streak,
                      value: '${stats.currentStreak}',
                      label: l10n.dayStreak,
                      color: const Color(0xFFD08700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricTile(
                      icon: AppIcons.reviews,
                      value: '${stats.todayReviews}',
                      label: l10n.reviewsToday,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricTile(
                      icon: AppIcons.percent,
                      value: stats.retentionSample == 0
                          ? '—'
                          : '${(stats.retention * 100).round()}%',
                      label: l10n.retention,
                      color: const Color(0xFF2E9E5B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      icon: AppIcons.card,
                      value: l10n.cardCount(stats.totalCards),
                      label: l10n.totalCards,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricTile(
                      icon: AppIcons.checkCircle,
                      value: '${stats.learnedCards}',
                      label: l10n.cardsStudied,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MetricTile(
                      icon: AppIcons.timer,
                      value: formatDuration(stats.totalStudyTime),
                      label: l10n.studyTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (stats.todayReviews > 0 || stats.dueToday > 0)
                Card(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              l10n.today,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            if (stats.dueToday > 0)
                              StatePill(
                                label: l10n.stillDue(stats.dueToday),
                                color: theme.colorScheme.error,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: stats.todayReviews == 0
                                ? 0
                                : (stats.todayReviews /
                                          (stats.todayReviews + stats.dueToday))
                                      .clamp(0.0, 1.0),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          stats.dueToday == 0
                              ? l10n.noCardsWaiting
                              : l10n.reviewedRemaining(
                                  stats.todayReviews,
                                  stats.dueToday,
                                ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (stats.totalReviews > 0) ...[
                const SizedBox(height: 20),
                SectionHeader(
                  title: l10n.reviewHeatmap,
                  subtitle: l10n.activeDaysLongest(
                    stats.activeDays,
                    stats.longestStreak,
                  ),
                ),
                Card(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 14, 14),
                    child: YearActivityHeatmap(logs: logs),
                  ),
                ),
                const SizedBox(height: 20),
                SectionHeader(
                  title: l10n.last30Days,
                  subtitle: l10n.reviewsPerDayChart,
                ),
                Card(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
                    child: ActivityBarChart(daily: stats.daily),
                  ),
                ),
                const SizedBox(height: 20),
                SectionHeader(
                  title: l10n.howYouRate,
                  subtitle: l10n.acrossReviews(stats.totalReviews),
                ),
                Card(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        RatingBreakdown(counts: stats.ratingCounts),
                        if (stats.retentionSample > 0) ...[
                          const Divider(height: 20),
                          Row(
                            children: [
                              Text(
                                l10n.estimatedRetention,
                                style: theme.textTheme.bodySmall,
                              ),
                              const Spacer(),
                              Text(
                                '${(stats.retention * 100).round()}%',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF2E9E5B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              l10n.basedOnScheduled(stats.retentionSample),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              if (collectionId == null) ...[
                const SizedBox(height: 20),
                SectionHeader(
                  title: l10n.collections,
                  subtitle: l10n.dueWorkloadByCollection,
                ),
                _DeckStatsList(collections: collections),
              ],
              const SizedBox(height: 20),
              SectionHeader(
                title: l10n.difficultCards,
                subtitle: l10n.cardsForgetMost,
              ),
              _DifficultCards(
                cards: cards,
                logs: logs,
                collectionId: collectionId,
              ),
              if (logs.isNotEmpty) ...[
                const SizedBox(height: 20),
                SectionHeader(
                  title: l10n.recentReviews,
                  subtitle: l10n.latestActivity,
                ),
                _RecentReviews(logs: logs),
              ],
              if (cards.isEmpty && collectionId == null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: EmptyState(
                    icon: AppIcons.insights,
                    title: l10n.noCardsStatsTitle,
                    message: l10n.noCardsStatsMessage,
                    compact: true,
                  ),
                ),
              if (deck != null &&
                  cards.isNotEmpty &&
                  deckMetrics.due == 0 &&
                  deckMetrics.newCards == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: EmptyState(
                    icon: AppIcons.checkCircle,
                    title: l10n.allScheduledDone,
                    message: l10n.allScheduledDoneMessage(deckMetrics.total),
                    compact: true,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DeckStatsList extends StatelessWidget {
  final List<Collection> collections;

  const _DeckStatsList({required this.collections});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final topLevel = collections
        .where((deck) => deck.parentId == null || deck.parentId!.isEmpty)
        .toList();
    if (topLevel.isEmpty) {
      return Text(
        l10n.noCollectionsStats,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final entries = <(Collection, DeckMetrics)>[
      for (final deck in topLevel)
        (
          deck,
          const StatsService().deckMetrics(
            HiveService.getCardsByCollection(deck.id),
          ),
        ),
    ];
    entries.sort(
      (a, b) => (b.$2.due + b.$2.newCards).compareTo(a.$2.due + a.$2.newCards),
    );

    return GroupedList(
      children: [
        for (final entry in entries)
          _DeckStatTile(deck: entry.$1, metrics: entry.$2),
      ],
    );
  }
}

class _DeckStatTile extends StatelessWidget {
  final Collection deck;
  final DeckMetrics metrics;

  const _DeckStatTile({required this.deck, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return ListTile(
      onTap: () {
        Navigator.push(
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
      },
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: deck.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: AppEmoji(deck.emoji, size: 20),
      ),
      title: Text(
        deck.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: metrics.progress,
              minHeight: 5,
              color: deck.color,
              backgroundColor: deck.color.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.dueCards(metrics.due)} · '
            '${l10n.newCards(metrics.newCards)} · '
            '${(metrics.progress * 100).round()}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: const Icon(AppIcons.chevronRight),
    );
  }
}

class _DifficultCards extends StatelessWidget {
  final List<CardItem> cards;
  final List<ReviewLog> logs;
  final String? collectionId;

  const _DifficultCards({
    required this.cards,
    required this.logs,
    this.collectionId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final difficult = const StatsService().difficultCards(
      cards: cards,
      logs: logs,
      limit: 5,
    );
    if (difficult.isEmpty) {
      return Card(
        color: theme.colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            cards.isEmpty ? l10n.noCardsToAnalyse : l10n.noDifficultCards,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          for (var index = 0; index < difficult.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            ListTile(
              onTap: () async {
                final result = await Navigator.push<CardEditorResult>(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => CreateCardScreen(
                      collectionId: difficult[index].collectionId,
                      card: difficult[index],
                    ),
                  ),
                );
                if (!context.mounted || result == null) return;
                final deleted = result.cards.isNotEmpty
                    ? result.cards
                    : [if (result.card != null) result.card!];
                if (result.deleted && deleted.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.cardDeleted),
                      action: SnackBarAction(
                        label: l10n.undo,
                        onPressed: () => HiveService.restoreCards(deleted),
                      ),
                    ),
                  );
                } else if (deleted.isNotEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.cardSaved)));
                }
              },
              leading: Icon(AppIcons.difficult, color: theme.colorScheme.error),
              title: Text(
                difficult[index].studyFront,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${l10n.lapsesLabel(difficult[index].lapses)} · '
                '${l10n.reviewCount(difficult[index].reps)}',
              ),
              trailing: const Icon(AppIcons.chevronRight),
            ),
          ],
          if (cards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push<bool>(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => StudyScreen(
                          deckIds: collectionId == null
                              ? HiveService.getAllCollections()
                                    .map((deck) => deck.id)
                                    .toList()
                              : [collectionId!],
                          title: l10n.difficultCards,
                          mode: StudyMode.difficult,
                          cards: cards,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(AppIcons.difficult, size: 18),
                  label: Text(l10n.practiceDifficultCards),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentReviews extends StatelessWidget {
  final List<ReviewLog> logs;

  const _RecentReviews({required this.logs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final sorted = List<ReviewLog>.from(logs)
      ..sort((a, b) => b.reviewedAt.compareTo(a.reviewedAt));
    final recent = sorted.take(8).toList();
    final cards = <String, CardItem>{};
    for (final log in recent) {
      final card = HiveService.getCard(log.cardId);
      if (card != null) cards[card.id] = card;
    }

    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          for (var index = 0; index < recent.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: _ratingColor(
                  theme,
                  recent[index].rating,
                ).withValues(alpha: 0.15),
                child: Text(
                  _ratingLetter(recent[index].rating),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _ratingColor(theme, recent[index].rating),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(
                cards[recent[index].cardId]?.studyFront ?? l10n.deletedCard,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${l10n.ratingLabel(recent[index].rating)} · '
                '${formatDate(recent[index].reviewedAt)} '
                '${formatClock(recent[index].reviewedAt.hour, recent[index].reviewedAt.minute)}'
                '${recent[index].mode == StudyMode.srs.name ? '' : ' · ${l10n.studyModeShortLabel(recent[index].studyMode)}'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: recent[index].durationMs > 0
                  ? Text(
                      formatDuration(
                        Duration(milliseconds: recent[index].durationMs),
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  static String _ratingLetter(int rating) => switch (rating) {
    1 => 'A',
    2 => 'H',
    3 => 'G',
    4 => 'E',
    _ => '?',
  };

  static Color _ratingColor(ThemeData theme, int rating) => switch (rating) {
    1 => theme.colorScheme.error,
    2 => const Color(0xFFD08700),
    3 => const Color(0xFF2E9E5B),
    4 => const Color(0xFF3A7BD5),
    _ => theme.colorScheme.primary,
  };
}
