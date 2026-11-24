import 'package:flutter/material.dart';
import 'package:knowit/theme/app_icons.dart';

/// Renders deck and card emoji with the supplied Apple Color Emoji font, with
/// Twemoji Mozilla as a redistributable fallback for unsupported glyphs or
/// platforms.
class AppEmoji extends StatelessWidget {
  final String emoji;
  final double size;
  final TextStyle? style;

  const AppEmoji(this.emoji, {super.key, this.size = 24, this.style});

  @override
  Widget build(BuildContext context) {
    if (emoji.trim().isEmpty) {
      return Icon(
        AppIcons.collection,
        size: size,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    return Text(
      emoji,
      style: (style ?? const TextStyle()).copyWith(
        fontFamily: 'AppleColorEmoji',
        fontFamilyFallback: const ['AppleColorEmoji', 'TwemojiMozilla'],
        fontSize: size,
        height: 1.1,
      ),
      textAlign: TextAlign.center,
    );
  }
}
