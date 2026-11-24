import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/theme/app_icons.dart';

IconData studyModeIcon(StudyMode mode) => switch (mode) {
  StudyMode.srs => AppIcons.schedule,
  StudyMode.quick => AppIcons.quick,
  StudyMode.cram => AppIcons.cram,
  StudyMode.random => AppIcons.random,
  StudyMode.difficult => AppIcons.difficult,
};

/// Lets the user choose a study mode. Returns null when dismissed.
Future<StudyMode?> showStudyModeSheet(
  BuildContext context, {
  String? deckName,
  StudyMode selected = StudyMode.srs,
}) {
  final l10n = context.l10n;
  return showModalBottomSheet<StudyMode>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deckName == null ? l10n.studyModes : l10n.studyDeck(deckName),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.onlySrsChanges,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                for (final mode in StudyMode.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: mode == selected
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.5,
                            )
                          : theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        onTap: () => Navigator.pop(context, mode),
                        leading: Icon(studyModeIcon(mode)),
                        title: Text(
                          l10n.studyModeLabel(mode),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(l10n.studyModeDescription(mode)),
                        trailing: mode.changesSchedule
                            ? null
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  l10n.noSchedule,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
