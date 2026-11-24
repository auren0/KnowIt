import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/services/anki/apkg_importer.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/import_progress.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/empty_state.dart';
import 'package:knowit/widgets/grouped_list.dart';
import 'package:knowit/widgets/rich_text.dart';

/// Preview + confirmation dialog for an Anki package with real progress reporting
/// and safe cancellation support.
class AnkiImportDialog extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;

  const AnkiImportDialog({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  @override
  State<AnkiImportDialog> createState() => _AnkiImportDialogState();
}

class _AnkiImportDialogState extends State<AnkiImportDialog> {
  static const AnkiImportService _service = AnkiImportService();

  AnkiImportPreview? _preview;
  String? _error;
  bool _loading = true;
  bool _importing = false;
  bool _skipDuplicates = true;

  final ValueNotifier<ImportProgress?> _progressNotifier = ValueNotifier(null);
  ImportCancellationToken? _cancellationToken;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void dispose() {
    _progressNotifier.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _progressNotifier.value = null;
    final token = ImportCancellationToken();
    _cancellationToken = token;

    try {
      final preview = await _service.previewBytes(
        widget.bytes,
        fileName: widget.fileName,
        onProgress: (prog) {
          _progressNotifier.value = prog;
        },
        cancellationToken: token,
      );
      if (!mounted) return;
      _progressNotifier.value = null;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } on ImportCancelledException {
      if (!mounted) return;
      Navigator.pop(context);
    } on AnkiFormatException catch (error) {
      if (!mounted) return;
      _progressNotifier.value = null;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      _progressNotifier.value = null;
      setState(() {
        _error = '${context.l10n.ankiImportCouldNotRead} $error';
        _loading = false;
      });
    } finally {
      _cancellationToken = null;
    }
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null || _importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    _progressNotifier.value = null;
    final token = ImportCancellationToken();
    _cancellationToken = token;

    try {
      final result = await _service.commit(
        preview,
        skipDuplicates: _skipDuplicates,
        onProgress: (prog) {
          _progressNotifier.value = prog;
        },
        cancellationToken: token,
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } on ImportCancelledException {
      if (!mounted) return;
      _progressNotifier.value = null;
      setState(() {
        _importing = false;
        _error = 'Import was cancelled. No changes were made.';
      });
    } on AnkiFormatException catch (error) {
      if (!mounted) return;
      _progressNotifier.value = null;
      setState(() {
        _error = error.message;
        _importing = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      _progressNotifier.value = null;
      setState(() {
        _error = context.l10n.importFailed(error);
        _importing = false;
      });
    } finally {
      _cancellationToken = null;
    }
  }

  void _cancel() {
    _cancellationToken?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final preview = _preview;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(AppIcons.box),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.ankiPreviewTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: KeyedSubtree(
            key: ValueKey(
              _loading
                  ? 'loading'
                  : _error != null && preview == null
                  ? 'error'
                  : 'preview',
            ),
            child: _loading
                ? SizedBox(
                    height: 160,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          ValueListenableBuilder<ImportProgress?>(
                            valueListenable: _progressNotifier,
                            builder: (context, progress, _) {
                              return Text(
                                progress?.stage ?? l10n.loading,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : _error != null && preview == null
                ? SingleChildScrollView(
                    child: InfoBanner(
                      icon: AppIcons.error,
                      message: _error!,
                      color: theme.colorScheme.error,
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_importing) ...[
                          ValueListenableBuilder<ImportProgress?>(
                            valueListenable: _progressNotifier,
                            builder: (context, progress, _) {
                              if (progress == null) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            progress.stage,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (!progress.isIndeterminate)
                                          Text(
                                            '${progress.percentage}%',
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: progress.fraction,
                                      borderRadius: BorderRadius.circular(4),
                                      minHeight: 6,
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        if (progress.detail != null)
                                          Text(
                                            progress.detail!,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          )
                                        else
                                          const SizedBox.shrink(),
                                        Text(
                                          progress.formatEta(
                                            isRussian: l10n.isRussian,
                                          ),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_error != null) ...[
                          InfoBanner(
                            icon: AppIcons.error,
                            message: _error!,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (preview != null) ...[
                          Text(
                            preview.sourceName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${l10n.noteCount(preview.noteCount)} · '
                            '${l10n.cardCount(preview.generatedCardCount)} · '
                            '${l10n.deckCount(preview.deckNames.length)} · '
                            '${l10n.mediaCount(preview.mediaCount)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (preview.warnings.isNotEmpty)
                            InfoBanner(
                              icon: AppIcons.info,
                              message: preview.warnings.take(6).join('\n'),
                              color: theme.colorScheme.tertiary,
                            ),
                          if (preview.warnings.length > 6) ...[
                            const SizedBox(height: 4),
                            Text(
                              l10n.moreNotices(preview.warnings.length - 6),
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                          const SizedBox(height: 14),
                          Text(
                            l10n.ankiDecks,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          GroupedList(
                            children: [
                              for (final entry
                                  in preview.deckCardCounts.entries.take(12))
                                ListTile(
                                  leading: const Icon(
                                    AppIcons.folder,
                                    size: 20,
                                  ),
                                  title: Text(
                                    entry.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  trailing: Text(
                                    l10n.cardCount(entry.value),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (preview.deckNames.length > 12)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                l10n.moreDecks(preview.deckNames.length - 12),
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                          const SizedBox(height: 14),
                          Text(
                            l10n.ankiSampleCards,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final note in preview.notes.take(3))
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  MarkupText(
                                    note.frontText,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (note.backText.trim().isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    MarkupText(
                                      note.backText,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          GroupedList(
                            children: [
                              SwitchListTile(
                                value: _skipDuplicates,
                                onChanged: _importing
                                    ? null
                                    : (value) => setState(
                                        () => _skipDuplicates = value,
                                      ),
                                title: Text(l10n.skipDuplicates),
                                subtitle: Text(l10n.skipDuplicatesSubtitle),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
      actions: [
        AppDialogActions(
          children: [
            TextButton(
              onPressed: _importing ? _cancel : () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            if (preview != null)
              FilledButton.icon(
                onPressed: _importing ? null : _import,
                icon: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.download, size: 18),
                label: Text(_importing ? l10n.importing : l10n.import),
              ),
            if (_error != null && preview == null)
              TextButton(onPressed: _parse, child: Text(l10n.retry)),
          ],
        ),
      ],
    );
  }
}
