import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/services/media_service.dart';
import 'package:knowit/theme/app_icons.dart';

final RegExp _markupPattern = RegExp(
  r'(\*\*([^*\n]+)\*\*|__([^_\n]+)__|==([^=\n]+)==|`([^`\n]+)`|\*([^*\n]+)\*)',
  multiLine: true,
);

/// Lightweight rich-text renderer used by cards and previews.
///
/// Supports `**bold**`, `*italic*`, `__underline__`, `==highlight==` and
/// `` `code` `` without pulling a full document editor into the app.
class MarkupText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool selectable;

  const MarkupText(
    this.text, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = (style ?? theme.textTheme.bodyLarge)?.copyWith(
      height: 1.45,
    );
    final spans = _buildSpans(context, baseStyle ?? const TextStyle());

    if (selectable) {
      return SelectableText.rich(
        TextSpan(children: spans),
        textAlign: textAlign,
        maxLines: maxLines,
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      style: baseStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  List<InlineSpan> _buildSpans(BuildContext context, TextStyle baseStyle) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in _markupPattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final bold = match.group(2);
      final underline = match.group(3);
      final highlight = match.group(4);
      final code = match.group(5);
      final italic = match.group(6);

      if (bold != null) {
        spans.add(
          TextSpan(
            text: bold,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (underline != null) {
        spans.add(
          TextSpan(
            text: underline,
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        );
      } else if (highlight != null) {
        spans.add(
          TextSpan(
            text: highlight,
            style: TextStyle(
              backgroundColor: scheme.primary.withValues(alpha: 0.22),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      } else if (code != null) {
        spans.add(
          TextSpan(
            text: code,
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontFamilyFallback: const ['AppleColorEmoji', 'TwemojiMozilla'],
              backgroundColor: scheme.surfaceContainerHighest,
              fontSize: (baseStyle.fontSize ?? 16) * 0.92,
            ),
          ),
        );
      } else if (italic != null) {
        spans.add(
          TextSpan(
            text: italic,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: text));
    return spans;
  }
}

/// Renders the full study face of a card: tags, formatted text, image, audio.
class CardContent extends StatelessWidget {
  final CardItem card;
  final bool showAnswer;
  final bool showTags;
  final bool compact;

  const CardContent({
    super.key,
    required this.card,
    required this.showAnswer,
    this.showTags = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = showAnswer ? card.studyBack : card.studyFront;
    final textStyle =
        (compact ? theme.textTheme.titleMedium : theme.textTheme.headlineSmall)
            ?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: theme.colorScheme.onSurface,
            );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTags && card.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in card.tags.take(6))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer.withValues(
                      alpha: 0.65,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$tag',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        MarkupText(text, style: textStyle, selectable: false),
        if (card.hasImage) ...[
          const SizedBox(height: 16),
          CardImage(path: card.imagePath!, maxHeight: compact ? 140 : 240),
        ],
        if (card.isPlayable) ...[
          const SizedBox(height: 14),
          AudioAttachmentButton(path: card.audioPath!, compact: compact),
        ],
      ],
    );
  }
}

class CardImage extends StatelessWidget {
  final String path;
  final double maxHeight;

  const CardImage({super.key, required this.path, this.maxHeight = 240});

  @override
  Widget build(BuildContext context) {
    if (!MediaService.exists(path)) {
      return _MissingAttachment(
        icon: AppIcons.imageOff,
        label: context.l10n.imageFileMissing,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => _MissingAttachment(
            icon: AppIcons.imageOff,
            label: context.l10n.imageLoadFailed,
          ),
        ),
      ),
    );
  }
}

class _MissingAttachment extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MissingAttachment({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact audio attachment control. Files are stored inside the app so this
/// works fully offline. Playback errors are shown instead of thrown.
class AudioAttachmentButton extends StatefulWidget {
  final String path;
  final bool compact;

  const AudioAttachmentButton({
    super.key,
    required this.path,
    this.compact = false,
  });

  @override
  State<AudioAttachmentButton> createState() => _AudioAttachmentButtonState();
}

class _AudioAttachmentButtonState extends State<AudioAttachmentButton> {
  AudioPlayer? _player;
  StreamSubscription<void>? _completeSubscription;
  bool _playing = false;
  String? _error;

  Future<AudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _player = player;
    _completeSubscription = player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    return player;
  }

  Future<void> _toggle() async {
    final l10n = context.l10n;
    final status = await MediaService.verifyAudio(widget.path);
    switch (status) {
      case AudioVerificationStatus.missingFile:
        if (mounted) setState(() => _error = l10n.audioFileMissing);
        return;
      case AudioVerificationStatus.unsupportedFormat:
        if (mounted) setState(() => _error = l10n.audioUnsupportedFormat);
        return;
      case AudioVerificationStatus.corruptedFile:
        if (mounted) setState(() => _error = l10n.audioFileCorrupted);
        return;
      case AudioVerificationStatus.valid:
        break;
    }

    final resolved = await MediaService.resolvePath(widget.path);
    if (resolved == null) {
      if (mounted) setState(() => _error = l10n.audioFileMissing);
      return;
    }

    try {
      final player = await _ensurePlayer();
      if (_playing) {
        await player.stop();
        if (mounted) setState(() => _playing = false);
      } else {
        await player.stop();
        await player.play(DeviceFileSource(resolved));
        if (mounted) {
          setState(() {
            _playing = true;
            _error = null;
          });
        }
      }
    } on Object catch (error) {
      if (mounted) {
        final msg = error.toString().toLowerCase();
        final String errorText;
        if (msg.contains('format') ||
            msg.contains('codec') ||
            msg.contains('unsupported')) {
          errorText = l10n.audioUnsupportedFormat;
        } else if (msg.contains('corrupt') ||
            msg.contains('decode') ||
            msg.contains('header')) {
          errorText = l10n.audioFileCorrupted;
        } else {
          errorText = l10n.audioPlaybackFailed;
        }
        setState(() {
          _playing = false;
          _error = errorText;
        });
      }
    }
  }

  @override
  void dispose() {
    _completeSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final label = _error ?? MediaService.displayName(widget.path);
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: widget.compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.8,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _playing ? AppIcons.pause : AppIcons.playCircle,
              size: widget.compact ? 20 : 24,
              color: _error == null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _playing ? l10n.audioPlaying : label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _error == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
