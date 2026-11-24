import 'package:flutter/material.dart';

/// Grouped list surface with context-aware corner radii:
/// first item rounds top corners, last item rounds bottom corners and middle
/// items stay square. A single item is rounded on all four corners.
///
/// The group owns separators and clipping, so individual screens never
/// hardcode border radii.
class GroupedList extends StatelessWidget {
  final List<Widget> children;
  final Color? color;
  final bool showDividers;
  final double radius;
  final EdgeInsetsGeometry? margin;

  const GroupedList({
    super.key,
    required this.children,
    this.color,
    this.showDividers = true,
    this.radius = 16,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = children.where((child) => child is! SizedBox).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final list = Material(
      color: color ?? theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            if (showDividers && index > 0)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant.withValues(
                  alpha: 0.5,
                ),
              ),
            ClipRRect(
              borderRadius: _radiusFor(index, visible.length),
              child: visible[index],
            ),
          ],
        ],
      ),
    );
    return margin == null ? list : Padding(padding: margin!, child: list);
  }

  BorderRadius _radiusFor(int index, int count) {
    if (count == 1) return BorderRadius.circular(radius);
    if (index == 0) {
      return BorderRadius.vertical(top: Radius.circular(radius));
    }
    if (index == count - 1) {
      return BorderRadius.vertical(bottom: Radius.circular(radius));
    }
    return BorderRadius.zero;
  }
}

/// A ListTile that supports the grouped interactions and state colours
/// without hardcoding corner radii at the call site.
class GroupedListTile extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  final bool destructive;
  final EdgeInsetsGeometry? contentPadding;

  const GroupedListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.enabled = true,
    this.destructive = false,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = destructive ? theme.colorScheme.error : null;
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
          : Colors.transparent,
      child: ListTile(
        enabled: enabled,
        selected: selected,
        contentPadding: contentPadding,
        onTap: enabled ? onTap : null,
        leading: leading == null
            ? null
            : IconTheme.merge(
                data: IconThemeData(color: tone),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: tone),
                  child: leading!,
                ),
              ),
        title: DefaultTextStyle.merge(
          style: TextStyle(color: tone),
          child: title ?? const SizedBox.shrink(),
        ),
        subtitle: subtitle == null
            ? null
            : DefaultTextStyle.merge(
                style: TextStyle(color: tone),
                child: subtitle!,
              ),
        trailing: trailing,
      ),
    );
  }
}
