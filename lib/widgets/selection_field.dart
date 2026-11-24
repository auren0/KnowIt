import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/grouped_list.dart';

class AppSelectOption<T> {
  final T value;
  final String label;
  final String? description;
  final IconData? icon;
  final bool enabled;

  const AppSelectOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
    this.enabled = true,
  });
}

/// Opens a polished selector: a searchable bottom sheet on phones and a
/// compact dialog on wider screens. Selection logic stays with the caller.
Future<T?> showAppSelect<T>(
  BuildContext context, {
  required String title,
  required List<AppSelectOption<T>> options,
  T? selected,
  bool searchable = true,
  String? searchHint,
}) {
  final effectiveSearchable = searchable && options.length > 8;
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 720) {
    return showDialog<T>(
      context: context,
      builder: (context) => _SelectionDialog<T>(
        title: title,
        options: options,
        selected: selected,
        searchable: effectiveSearchable,
        searchHint: searchHint,
        maxWidth: 520,
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SelectionSheet<T>(
      title: title,
      options: options,
      selected: selected,
      searchable: effectiveSearchable,
      searchHint: searchHint,
    ),
  );
}

class AppSelectField<T> extends StatelessWidget {
  final String label;
  final String? valueLabel;
  final IconData? leadingIcon;
  final bool enabled;
  final bool dense;
  final VoidCallback? onTap;
  final List<AppSelectOption<T>>? options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final String? sheetTitle;
  final bool searchable;

  const AppSelectField({
    super.key,
    required this.label,
    required this.valueLabel,
    this.onTap,
    this.leadingIcon,
    this.enabled = true,
    this.dense = false,
    this.options,
    this.value,
    this.onChanged,
    this.sheetTitle,
    this.searchable = true,
  });

  Future<void> _open(BuildContext context) async {
    final onTap = this.onTap;
    if (onTap != null) {
      onTap();
      return;
    }
    final options = this.options;
    final onChanged = this.onChanged;
    if (options == null || onChanged == null) return;
    final result = await showAppSelect<T>(
      context,
      title: sheetTitle ?? label,
      options: options,
      selected: value,
      searchable: searchable,
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        isEmpty: valueLabel == null || valueLabel!.isEmpty,
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          contentPadding: dense
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
              : null,
          prefixIcon: leadingIcon == null ? null : Icon(leadingIcon, size: 20),
          suffixIcon: Icon(
            AppIcons.chevronDown,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        child: Text(
          valueLabel ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _SelectionSheet<T> extends StatefulWidget {
  final String title;
  final List<AppSelectOption<T>> options;
  final T? selected;
  final bool searchable;
  final String? searchHint;

  const _SelectionSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchable,
    this.searchHint,
  });

  @override
  State<_SelectionSheet<T>> createState() => _SelectionSheetState<T>();
}

class _SelectionSheetState<T> extends State<_SelectionSheet<T>> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<AppSelectOption<T>> get _filtered {
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where(
          (option) =>
              option.label.toLowerCase().contains(query) ||
              (option.description ?? '').toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final filtered = _filtered;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.94,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Icon(
                  AppIcons.check,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _controller,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.searchHint ?? l10n.searchCollections,
                  prefixIcon: const Icon(AppIcons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.clearSearch,
                          onPressed: () {
                            _controller.clear();
                            setState(() {});
                          },
                          icon: const Icon(AppIcons.clear),
                        ),
                ),
              ),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      l10n.noMatchingCollections,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    children: [
                      FocusTraversalGroup(
                        policy: ReadingOrderTraversalPolicy(),
                        child: GroupedList(
                          children: [
                            for (final option in filtered)
                              _OptionTile<T>(
                                option: option,
                                selected: option.value == widget.selected,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SelectionDialog<T> extends StatefulWidget {
  final String title;
  final List<AppSelectOption<T>> options;
  final T? selected;
  final bool searchable;
  final String? searchHint;
  final double maxWidth;

  const _SelectionDialog({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchable,
    required this.searchHint,
    required this.maxWidth,
  });

  @override
  State<_SelectionDialog<T>> createState() => _SelectionDialogState<T>();
}

class _SelectionDialogState<T> extends State<_SelectionDialog<T>> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<AppSelectOption<T>> get _filtered {
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where(
          (option) =>
              option.label.toLowerCase().contains(query) ||
              (option.description ?? '').toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final filtered = _filtered;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: widget.maxWidth,
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          children: [
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _controller,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: widget.searchHint ?? l10n.searchCollections,
                    prefixIcon: const Icon(AppIcons.search),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l10n.clearSearch,
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                            icon: const Icon(AppIcons.clear),
                          ),
                  ),
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        l10n.noMatchingCollections,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: FocusTraversalGroup(
                        policy: ReadingOrderTraversalPolicy(),
                        child: GroupedList(
                          children: [
                            for (final option in filtered)
                              _OptionTile<T>(
                                option: option,
                                selected: option.value == widget.selected,
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        AppDialogActions(
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ],
    );
  }
}

class _OptionTile<T> extends StatelessWidget {
  final AppSelectOption<T> option;
  final bool selected;

  const _OptionTile({required this.option, required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GroupedListTile(
      enabled: option.enabled,
      selected: selected,
      onTap: option.enabled
          ? () {
              HapticFeedback.selectionClick();
              Navigator.pop(context, option.value);
            }
          : null,
      leading: option.icon == null
          ? null
          : Icon(
              option.icon,
              color: selected ? theme.colorScheme.primary : null,
            ),
      title: Text(
        option.label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: option.description == null ? null : Text(option.description!),
      trailing: selected
          ? Icon(AppIcons.check, color: theme.colorScheme.primary, size: 22)
          : null,
    );
  }
}
