import 'package:flutter/material.dart';

/// Shared dialog layout and action bar.
///
/// All confirmation dialogs use the same button height, padding, corner radius
/// and spacing. On very narrow screens actions stack vertically so long
/// translated labels never overflow.
class AppDialog extends StatelessWidget {
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final bool scrollable;
  final EdgeInsetsGeometry? contentPadding;

  const AppDialog({
    super.key,
    this.title,
    this.content,
    required this.actions,
    this.scrollable = true,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: scrollable,
      title: title,
      contentPadding: contentPadding,
      content: content,
      actions: [AppDialogActions(children: actions)],
    );
  }
}

class AppDialogActions extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment alignment;

  const AppDialogActions({
    super.key,
    required this.children,
    this.alignment = MainAxisAlignment.end,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final narrow = MediaQuery.sizeOf(context).width < 380;
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _sized(children[index]),
          ],
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [for (final child in children) _sized(child)],
    );
  }

  Widget _sized(Widget child) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 88),
      child: child,
    );
  }
}

/// Consistent destructive primary action.
ButtonStyle destructiveButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.error,
    foregroundColor: Theme.of(context).colorScheme.onError,
  );
}

/// Shared confirmation helper used by destructive and irreversible actions.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  Widget? content,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      title: Text(title),
      content: content ?? Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            cancelLabel ?? MaterialLocalizations.of(context).cancelButtonLabel,
          ),
        ),
        FilledButton(
          style: destructive ? destructiveButtonStyle(dialogContext) : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            confirmLabel ?? MaterialLocalizations.of(context).okButtonLabel,
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
