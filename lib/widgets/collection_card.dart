import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/services/stats_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/formatters.dart';
import 'package:knowit/widgets/app_emoji.dart';
import 'package:knowit/widgets/insights.dart';

/// Deck card: emoji, accent colour, counts and a progress section that never
/// competes with the overflow menu.
class DeckCard extends StatelessWidget {
  final Collection collection;
  final DeckMetrics metrics;
  final int depth;
  final VoidCallback? onTap;
  final VoidCallback? onStudy;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onAddSubdeck;
  final VoidCallback? onDelete;
  final bool showMenu;

  const DeckCard({
    super.key,
    required this.collection,
    required this.metrics,
    this.depth = 0,
    this.onTap,
    this.onStudy,
    this.onEdit,
    this.onDuplicate,
    this.onAddSubdeck,
    this.onDelete,
    this.showMenu = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final accent = collection.color;
    final accentText =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.light
        ? Color.lerp(accent, Colors.black, 0.5)!
        : accent;
    final dueLabel = metrics.due > 0
        ? l10n.dueCards(metrics.due)
        : metrics.nextDue != null
        ? l10n.nextDueLabel(formatRelativeDue(metrics.nextDue!))
        : metrics.total == 0
        ? l10n.noCardsYet
        : l10n.allCaughtUp;

    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: Card(
        elevation: 1,
        color: theme.colorScheme.surfaceContainerLow,
        surfaceTintColor: accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: depth > 0
              ? BorderSide(color: accent.withValues(alpha: 0.18))
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: AppEmoji(collection.emoji, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (depth > 0) ...[
                                Icon(
                                  AppIcons.subfolder,
                                  size: 15,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  collection.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (collection.description.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              collection.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                l10n.cardCount(metrics.total),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: accentText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (metrics.newCards > 0)
                                StatePill(
                                  label: l10n.newCards(metrics.newCards),
                                  color: theme.colorScheme.tertiary,
                                ),
                              if (metrics.due > 0)
                                StatePill(
                                  label: l10n.dueCards(metrics.due),
                                  color: theme.colorScheme.error,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (showMenu)
                      PopupMenuButton<String>(
                        tooltip: l10n.deckOptions,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        iconSize: 20,
                        icon: Icon(
                          AppIcons.more,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'study':
                              onStudy?.call();
                            case 'edit':
                              onEdit?.call();
                            case 'subdeck':
                              onAddSubdeck?.call();
                            case 'duplicate':
                              onDuplicate?.call();
                            case 'delete':
                              onDelete?.call();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'study',
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              leading: const Icon(AppIcons.play),
                              title: Text(l10n.study),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              leading: const Icon(AppIcons.edit),
                              title: Text(l10n.editDeck),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'subdeck',
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              leading: const Icon(AppIcons.folderAdd),
                              title: Text(l10n.addSubdeck),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'duplicate',
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              leading: const Icon(AppIcons.copy),
                              title: Text(l10n.duplicate),
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              leading: Icon(
                                AppIcons.delete,
                                color: theme.colorScheme.error,
                              ),
                              title: Text(
                                l10n.delete,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: metrics.progress.clamp(0.0, 1.0),
                          minHeight: 7,
                          color: accentText,
                          backgroundColor: accent.withValues(alpha: 0.14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${(metrics.progress * 100).round()}%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: accentText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        dueLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
