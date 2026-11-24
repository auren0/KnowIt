import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/review_log.dart';
import 'package:knowit/services/stats_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/formatters.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  const MetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = color ?? theme.colorScheme.primary;
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: tone),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final Color color;
  final String? centerLabel;
  final String? caption;

  const ProgressRing({
    super.key,
    required this.value,
    this.size = 96,
    required this.color,
    this.centerLabel,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = value.clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: clamped,
                  strokeWidth: math.max(5, size * 0.075),
                  strokeCap: StrokeCap.round,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.16),
                ),
              ),
              Text(
                centerLabel ?? '${(clamped * 100).round()}%',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontSize: size * 0.18,
                ),
              ),
            ],
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 8),
          Text(
            caption!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class StatePill extends StatelessWidget {
  final String label;
  final Color color;

  const StatePill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// GitHub-style activity heatmap built from real review logs.
class ReviewHeatmap extends StatelessWidget {
  final Map<String, int> data;
  final int weeks;

  const ReviewHeatmap({super.key, required this.data, this.weeks = 17});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = startOfDay(now);
    final thisWeekStart = startOfWeek(today);
    final maxCount = data.values.fold<int>(0, math.max);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 3.0;
        final available = constraints.maxWidth;
        final maxWeeks = math.max(1, ((available + gap) / (13 + gap)).floor());
        final usedWeeks = math.min(weeks, maxWeeks);
        final cell = math.min(
          14.0,
          (available - gap * (usedWeeks - 1)) / usedWeeks,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: cell * 7 + gap * 6,
              child: Row(
                children: [
                  for (var week = 0; week < usedWeeks; week++) ...[
                    if (week > 0) const SizedBox(width: gap),
                    Column(
                      children: [
                        for (var day = 0; day < 7; day++) ...[
                          if (day > 0) const SizedBox(height: gap),
                          _HeatCell(
                            size: cell,
                            date: thisWeekStart
                                .subtract(
                                  Duration(days: (usedWeeks - 1 - week) * 7),
                                )
                                .add(Duration(days: day)),
                            today: today,
                            maxCount: maxCount,
                            data: data,
                            color: theme.colorScheme.primary,
                            emptyColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${usedWeeks * 7} days',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  'Less',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                for (final level in [0.0, 0.25, 0.45, 0.7, 1.0]) ...[
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: level == 0
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.primary.withValues(alpha: level),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
                const SizedBox(width: 2),
                Text(
                  'More',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _HeatCell extends StatelessWidget {
  final double size;
  final DateTime date;
  final DateTime today;
  final int maxCount;
  final Map<String, int> data;
  final Color color;
  final Color emptyColor;
  final bool visible;

  const _HeatCell({
    required this.size,
    required this.date,
    required this.today,
    required this.maxCount,
    required this.data,
    required this.color,
    required this.emptyColor,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible || date.isAfter(today)) {
      return SizedBox(width: size, height: size);
    }
    final count = data[dayKey(date)] ?? 0;
    final ratio = maxCount == 0 ? 0.0 : count / maxCount;
    final alpha = count == 0 ? 0.0 : (0.28 + ratio * 0.62).clamp(0.28, 0.95);
    final cell = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: count == 0 ? emptyColor : color.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(math.max(2, size * 0.18)),
      ),
    );
    return Tooltip(
      message:
          '${formatDayMonth(date)} · '
          '${context.l10n.reviewCount(count)}',
      waitDuration: const Duration(milliseconds: 300),
      child: cell,
    );
  }
}

/// A full-year activity heatmap built entirely from persisted review logs.
///
/// It is horizontally scrollable so the cells stay readable on phones, and
/// navigation never goes beyond the current year. Leap years are handled by
/// generating the grid from real calendar dates.
class YearActivityHeatmap extends StatefulWidget {
  final List<ReviewLog> logs;
  final int? initialYear;

  const YearActivityHeatmap({super.key, required this.logs, this.initialYear});

  @override
  State<YearActivityHeatmap> createState() => _YearActivityHeatmapState();
}

class _YearActivityHeatmapState extends State<YearActivityHeatmap> {
  final ScrollController _scrollController = ScrollController();
  late int _year;
  bool _jumped = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().year;
    _year = math.min(widget.initialYear ?? now, now);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Map<String, int> get _data {
    final result = <String, int>{};
    for (final log in widget.logs) {
      if (log.reviewedAt.year != _year) continue;
      final key = dayKey(log.reviewedAt);
      result[key] = (result[key] ?? 0) + 1;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = startOfDay(now);
    final currentYear = now.year;
    final data = _data;
    final maxCount = data.values.fold<int>(0, math.max);
    final firstDay = DateTime(_year, 1, 1);
    final lastDay = DateTime(_year, 12, 31);
    final gridStart = startOfWeek(firstDay);
    final weeks = (startOfDay(lastDay).difference(gridStart).inDays ~/ 7) + 1;
    final activeDays = data.values.where((count) => count > 0).length;
    final total = data.values.fold<int>(0, (sum, count) => sum + count);
    const gap = 3.0;
    const cell = 12.0;

    if (!_jumped) {
      _jumped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        if (_year == currentYear) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.previousYear,
              onPressed: () => setState(() => _year -= 1),
              icon: const Icon(AppIcons.chevronLeft),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '$_year',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      l10n.activityForYear(_year, total, activeDays),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.nextYear,
              onPressed: _year >= currentYear
                  ? null
                  : () => setState(() => _year += 1),
              icon: const Icon(AppIcons.chevronRight),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: cell * 7 + gap * 6,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: weeks * (cell + gap) > 320,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var week = 0; week < weeks; week++) ...[
                    if (week > 0) const SizedBox(width: gap),
                    Column(
                      children: [
                        for (var day = 0; day < 7; day++) ...[
                          if (day > 0) const SizedBox(height: gap),
                          _HeatCell(
                            size: cell,
                            date: gridStart.add(Duration(days: week * 7 + day)),
                            today: today,
                            maxCount: maxCount,
                            data: data,
                            color: theme.colorScheme.primary,
                            emptyColor:
                                theme.colorScheme.surfaceContainerHighest,
                            visible:
                                gridStart
                                    .add(Duration(days: week * 7 + day))
                                    .year ==
                                _year,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              l10n.less,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            for (final level in [0.0, 0.25, 0.45, 0.7, 1.0]) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: level == 0
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.primary.withValues(alpha: level),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 2),
            ],
            const SizedBox(width: 2),
            Text(
              l10n.more,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              l10n.dayCount(activeDays),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Last 30 days of real review activity. New cards are highlighted inside the
/// daily bars so the chart shows both volume and learning progress.
class ActivityBarChart extends StatelessWidget {
  final List<DailyActivity> daily;
  final double height;

  const ActivityBarChart({super.key, required this.daily, this.height = 132});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (daily.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxValue = daily.fold<int>(
      0,
      (max, day) => math.max(max, day.reviews),
    );
    return Column(
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < daily.length; index++) ...[
                if (index > 0) const SizedBox(width: 2),
                Expanded(
                  child: _ActivityBar(
                    day: daily[index],
                    maxValue: math.max(maxValue, 1),
                    reviewsColor: theme.colorScheme.primary,
                    newColor: theme.colorScheme.tertiary,
                    emptyColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatDayMonth(daily.first.date),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              context.l10n.dayCount(daily.length),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              formatDayMonth(daily.last.date),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActivityBar extends StatelessWidget {
  final DailyActivity day;
  final int maxValue;
  final Color reviewsColor;
  final Color newColor;
  final Color emptyColor;

  const _ActivityBar({
    required this.day,
    required this.maxValue,
    required this.reviewsColor,
    required this.newColor,
    required this.emptyColor,
  });

  @override
  Widget build(BuildContext context) {
    final reviews = day.reviews;
    final newCards = math.min(day.newCards, reviews);
    final totalRatio = reviews / maxValue;
    final newRatio = reviews == 0 ? 0.0 : newCards / reviews;

    return Tooltip(
      message:
          '${formatDayMonth(day.date)}\n'
          '${context.l10n.reviewCount(reviews)}'
          '${newCards > 0 ? ' · ${context.l10n.newCards(newCards)}' : ''}',
      waitDuration: const Duration(milliseconds: 250),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barHeight = math.max(
            reviews == 0 ? 3.0 : 6.0,
            constraints.maxHeight * totalRatio,
          );
          return Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: barHeight,
              decoration: BoxDecoration(
                color: reviews == 0 ? emptyColor : reviewsColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: newRatio == 0
                  ? null
                  : Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: newRatio.clamp(0.0, 1.0),
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: newColor.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class RatingBreakdown extends StatelessWidget {
  final Map<int, int> counts;

  const RatingBreakdown({super.key, required this.counts});

  static const List<int> _values = [1, 2, 3, 4];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    final colors = [
      theme.colorScheme.error,
      const Color(0xFFE08A00),
      const Color(0xFF2E9E5B),
      const Color(0xFF3A7BD5),
    ];

    return Column(
      children: [
        for (var index = 0; index < _values.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    l10n.ratingLabel(_values[index]),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: total == 0
                          ? 0
                          : (counts[_values[index]] ?? 0) / total,
                      minHeight: 8,
                      color: colors[index],
                      backgroundColor: colors[index].withValues(alpha: 0.12),
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${counts[_values[index]] ?? 0}',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A data-driven recommendation card.
class SuggestionCard extends StatelessWidget {
  final StudySuggestion suggestion;
  final VoidCallback onAction;

  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: InkWell(
        onTap: onAction,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  AppIcons.sparkle,
                  size: 19,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      suggestion.message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      suggestion.actionLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                AppIcons.chevronRight,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
