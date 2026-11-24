import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/screens/ai_generate_screen.dart';
import 'package:knowit/screens/ai_settings_dialog.dart';
import 'package:knowit/screens/anki_import_dialog.dart';
import 'package:knowit/services/ai_service.dart';
import 'package:knowit/services/anki/apkg_exporter.dart';
import 'package:knowit/services/anki/apkg_importer.dart';
import 'package:knowit/services/backup_service.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/notification_service.dart';
import 'package:knowit/services/settings_service.dart';
import 'package:knowit/services/sync/tombstone_store.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/formatters.dart';
import 'package:knowit/utils/import_progress.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/app_emoji.dart';
import 'package:knowit/widgets/empty_state.dart';
import 'package:knowit/widgets/grouped_list.dart';
import 'package:knowit/widgets/insights.dart';
import 'package:knowit/widgets/selection_field.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const String appVersion = '1.0.0';

  AppSettings get _settings => SettingsService.value;

  Future<void> _save(
    BuildContext context,
    AppSettings settings, {
    bool applyReminders = false,
  }) async {
    await SettingsService.save(settings);
    if (!applyReminders) return;
    final applied = await NotificationService.applySettings(settings);
    if (!applied && settings.remindersEnabled && context.mounted) {
      await SettingsService.save(
        SettingsService.value.copyWith(remindersEnabled: false),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.remindersPermissionFailed)),
        );
      }
    }
  }

  Future<void> _setReminderEnabled(BuildContext context, bool enabled) async {
    if (!enabled) {
      await SettingsService.update(
        (settings) => settings.copyWith(remindersEnabled: false),
      );
      await NotificationService.cancel();
      return;
    }
    final candidate = _settings.copyWith(remindersEnabled: true);
    final ok = await NotificationService.applySettings(candidate);
    if (!ok) {
      await SettingsService.update(
        (settings) => settings.copyWith(remindersEnabled: false),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.notificationsDenied)),
        );
      }
      return;
    }
    await SettingsService.save(candidate);
  }

  Future<void> _pickReminderTime(BuildContext context) async {
    final current = _settings;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: current.reminderHour,
        minute: current.reminderMinute,
      ),
    );
    if (selected == null || !context.mounted) return;
    final updated = current.copyWith(
      reminderHour: selected.hour,
      reminderMinute: selected.minute,
    );
    if (updated.remindersEnabled) {
      await _save(context, updated, applyReminders: true);
    } else {
      await SettingsService.save(updated);
    }
  }

  Future<void> _editSteps(
    BuildContext context, {
    required bool learning,
  }) async {
    final current = learning
        ? _settings.learningStepsMinutes
        : _settings.relearningStepsMinutes;
    final controller = TextEditingController(text: current.join(', '));
    String? error;
    final result = await showDialog<List<int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            learning
                ? context.l10n.learningSteps
                : context.l10n.relearningSteps,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.l10n.minutesCommaSeparated,
                  hintText: learning ? '1, 10' : '10',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                learning
                    ? context.l10n.learningStepsHelp
                    : context.l10n.relearningStepsHelp,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final raw = controller.text.trim();
                    final steps = <int>[];
                    if (raw.isNotEmpty) {
                      for (final part in raw.split(',')) {
                        final value = int.tryParse(part.trim());
                        if (value == null || value < 1 || value > 1440) {
                          setState(() => error = context.l10n.stepsValidation);
                          return;
                        }
                        steps.add(value);
                      }
                    }
                    setState(() => error = null);
                    Navigator.pop(context, steps.toSet().toList()..sort());
                  },
                  child: Text(context.l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;
    await SettingsService.update(
      (settings) => learning
          ? settings.copyWith(learningStepsMinutes: result)
          : settings.copyWith(relearningStepsMinutes: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<AppSettings>(
      valueListenable: SettingsService.notifier,
      builder: (context, settings, _) {
        return Scaffold(
          appBar: AppBar(title: Text(l10n.settings)),
          body: AnimatedBuilder(
            animation: Listenable.merge([
              HiveService.collectionsListenable,
              HiveService.cardsListenable,
              HiveService.logsListenable,
            ]),
            builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                _AppearanceSection(settings: settings),
                const SizedBox(height: 20),
                _StudySection(
                  settings: settings,
                  onChanged: (value) => _save(context, value),
                  onEditLearning: () => _editSteps(context, learning: true),
                  onEditRelearning: () => _editSteps(context, learning: false),
                ),
                const SizedBox(height: 20),
                _RemindersSection(
                  settings: settings,
                  onToggle: (value) => _setReminderEnabled(context, value),
                  onPickTime: () => _pickReminderTime(context),
                ),
                const SizedBox(height: 20),
                const _DataSection(),
                const SizedBox(height: 20),
                const _SyncSection(),
                const SizedBox(height: 20),
                const _AiSection(),
                const SizedBox(height: 20),
                const _AboutSection(version: appVersion),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _SettingsCard({
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, subtitle: subtitle),
        GroupedList(children: children),
      ],
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  final AppSettings settings;

  const _AppearanceSection({required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _SettingsCard(
      title: l10n.appearance,
      subtitle: l10n.appearanceSubtitle,
      children: [
        ListTile(
          leading: const Icon(AppIcons.language),
          title: Text(l10n.language),
          subtitle: Text(settings.language.nativeLabel),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () async {
            final selected = await showAppSelect<AppLanguage>(
              context,
              title: l10n.language,
              selected: settings.language,
              options: [
                for (final language in AppLanguage.values)
                  AppSelectOption(
                    value: language,
                    label: language.nativeLabel,
                    icon: AppIcons.language,
                  ),
              ],
            );
            if (selected != null) {
              await SettingsService.update(
                (current) => current.copyWith(language: selected),
              );
              final updated = SettingsService.value;
              if (updated.remindersEnabled) {
                await NotificationService.applySettings(updated);
              }
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.theme, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemePreference>(
                  segments: [
                    for (final preference in ThemePreference.values)
                      ButtonSegment(
                        value: preference,
                        label: Text(l10n.themeLabel(preference)),
                      ),
                  ],
                  selected: {settings.theme},
                  onSelectionChanged: (value) {
                    SettingsService.update(
                      (current) => current.copyWith(theme: value.first),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.accentColor, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                l10n.accentColorHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  for (final accent in AccentColor.values)
                    Semantics(
                      button: true,
                      selected: settings.accentColor == accent,
                      label: l10n.accentLabel(accent),
                      child: Tooltip(
                        message: l10n.accentLabel(accent),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () {
                            SettingsService.update(
                              (current) =>
                                  current.copyWith(accentColor: accent),
                            );
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.seed,
                              border: Border.all(
                                width: settings.accentColor == accent ? 3 : 1,
                                color: settings.accentColor == accent
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: settings.accentColor == accent
                                ? Icon(
                                    AppIcons.check,
                                    size: 20,
                                    color:
                                        ThemeData.estimateBrightnessForColor(
                                              accent.seed,
                                            ) ==
                                            Brightness.light
                                        ? Colors.black87
                                        : Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.fontFamily, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                l10n.fontFamilyHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<AppFontFamily>(
                  segments: [
                    for (final font in AppFontFamily.values)
                      ButtonSegment(
                        value: font,
                        label: Text(
                          l10n.fontLabel(font),
                          style: TextStyle(fontFamily: font.family),
                        ),
                      ),
                  ],
                  selected: {settings.fontFamily},
                  onSelectionChanged: (value) {
                    SettingsService.update(
                      (current) => current.copyWith(fontFamily: value.first),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    AppIcons.fontSize,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.textSize,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${(settings.textScale * 100).round()}%',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Slider(
                value: settings.textScale,
                min: 0.8,
                max: 1.4,
                divisions: 6,
                label: '${(settings.textScale * 100).round()}%',
                onChanged: (value) {
                  SettingsService.update(
                    (current) => current.copyWith(textScale: value),
                  );
                },
              ),
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(AppIcons.sparkle),
          title: Text(l10n.animations),
          subtitle: Text(l10n.cardFlipAnimation),
          value: settings.animationsEnabled,
          onChanged: (value) {
            SettingsService.update(
              (current) => current.copyWith(animationsEnabled: value),
            );
          },
        ),
        SwitchListTile(
          secondary: const Icon(AppIcons.move),
          title: Text(l10n.swipeToRate),
          subtitle: Text(l10n.swipeToRateSubtitle),
          value: settings.swipeToRate,
          onChanged: (value) {
            SettingsService.update(
              (current) => current.copyWith(swipeToRate: value),
            );
          },
        ),
        SwitchListTile(
          secondary: const Icon(AppIcons.tap),
          title: Text(l10n.hapticFeedback),
          subtitle: Text(l10n.hapticFeedbackSubtitle),
          value: settings.hapticFeedback,
          onChanged: (value) {
            SettingsService.update(
              (current) => current.copyWith(hapticFeedback: value),
            );
          },
        ),
        SwitchListTile(
          secondary: const Icon(AppIcons.key),
          title: Text(l10n.keyboardShortcuts),
          subtitle: Text(l10n.keyboardShortcutsSubtitle),
          value: settings.keyboardShortcuts,
          onChanged: (value) {
            SettingsService.update(
              (current) => current.copyWith(keyboardShortcuts: value),
            );
          },
        ),
      ],
    );
  }
}

class _StudySection extends StatelessWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;
  final VoidCallback onEditLearning;
  final VoidCallback onEditRelearning;

  const _StudySection({
    required this.settings,
    required this.onChanged,
    required this.onEditLearning,
    required this.onEditRelearning,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _SettingsCard(
      title: l10n.studySection,
      subtitle: l10n.studySectionSubtitle,
      children: [
        _NumberSetting(
          title: l10n.newCardsPerDay,
          value: settings.newCardsPerDay,
          min: 0,
          max: 500,
          step: 1,
          onChanged: (value) =>
              onChanged(settings.copyWith(newCardsPerDay: value)),
        ),
        _NumberSetting(
          title: l10n.reviewsPerDay,
          value: settings.reviewsPerDay,
          min: 0,
          max: 2000,
          step: 10,
          onChanged: (value) =>
              onChanged(settings.copyWith(reviewsPerDay: value)),
        ),
        _NumberSetting(
          title: l10n.dailyGoal,
          value: settings.dailyGoal,
          min: 0,
          max: 1000,
          step: 5,
          onChanged: (value) => onChanged(settings.copyWith(dailyGoal: value)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.desiredRetention,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '${(settings.desiredRetention * 100).round()}%',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Slider(
                value: settings.desiredRetention,
                min: 0.70,
                max: 0.97,
                divisions: 27,
                label: '${(settings.desiredRetention * 100).round()}%',
                onChanged: (value) => onChanged(
                  settings.copyWith(
                    desiredRetention: (value * 100).round() / 100,
                  ),
                ),
              ),
              Text(
                l10n.retentionHelp,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(AppIcons.schedule),
          onTap: onEditLearning,
          title: Text(l10n.learningSteps),
          subtitle: Text(
            settings.learningStepsMinutes.isEmpty
                ? l10n.graduateImmediately
                : l10n.minutesList(settings.learningStepsMinutes),
          ),
          trailing: const Icon(AppIcons.chevronRight),
        ),
        ListTile(
          leading: const Icon(AppIcons.refresh),
          onTap: onEditRelearning,
          title: Text(l10n.relearningSteps),
          subtitle: Text(
            settings.relearningStepsMinutes.isEmpty
                ? l10n.returnToReviewImmediately
                : l10n.minutesList(settings.relearningStepsMinutes),
          ),
          trailing: const Icon(AppIcons.chevronRight),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    AppIcons.eye,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.answerReveal,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                l10n.answerRevealHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<AnswerRevealMode>(
                  segments: [
                    ButtonSegment(
                      value: AnswerRevealMode.flip,
                      icon: const Icon(AppIcons.random, size: 18),
                      label: Text(l10n.flipAnimation),
                    ),
                    ButtonSegment(
                      value: AnswerRevealMode.instant,
                      icon: const Icon(AppIcons.quick, size: 18),
                      label: Text(l10n.instantReveal),
                    ),
                  ],
                  selected: {settings.answerRevealMode},
                  onSelectionChanged: (value) {
                    onChanged(settings.copyWith(answerRevealMode: value.first));
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                settings.answerRevealMode == AnswerRevealMode.flip
                    ? l10n.flipAnimationDescription
                    : l10n.instantRevealDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.reducedMotionNote,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text(
            l10n.studyFootnote,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _NumberSetting extends StatelessWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  const _NumberSetting({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          IconButton(
            tooltip: context.l10n.less,
            onPressed: value <= min
                ? null
                : () => onChanged((value - step).clamp(min, max)),
            icon: const Icon(AppIcons.subtractCircle),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: context.l10n.more,
            onPressed: value >= max
                ? null
                : () => onChanged((value + step).clamp(min, max)),
            icon: const Icon(AppIcons.addCircle),
          ),
        ],
      ),
    );
  }
}

class _RemindersSection extends StatelessWidget {
  final AppSettings settings;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;

  const _RemindersSection({
    required this.settings,
    required this.onToggle,
    required this.onPickTime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _SettingsCard(
      title: l10n.reminders,
      children: [
        SwitchListTile(
          secondary: const Icon(AppIcons.reminder),
          title: Text(l10n.dailyStudyReminder),
          subtitle: Text(
            settings.remindersEnabled
                ? l10n.everyDayAt(
                    formatTimeOfDayValue(
                      settings.reminderHour,
                      settings.reminderMinute,
                    ),
                  )
                : l10n.remindersOff,
          ),
          value: settings.remindersEnabled,
          onChanged: onToggle,
        ),
        ListTile(
          enabled: settings.remindersEnabled,
          onTap: settings.remindersEnabled ? onPickTime : null,
          leading: const Icon(AppIcons.schedule),
          title: Text(l10n.reminderTime),
          trailing: Text(
            formatTimeOfDayValue(
              settings.reminderHour,
              settings.reminderMinute,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text(
            l10n.remindersFootnote,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _DataSection extends StatelessWidget {
  const _DataSection();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cards = HiveService.getAllCards().length;
    final logs = HiveService.getAllLogs().length;
    final collections = HiveService.getAllCollections().length;
    final theme = Theme.of(context);
    return _SettingsCard(
      title: l10n.data,
      subtitle: l10n.dataSubtitle,
      children: [
        ListTile(
          leading: const Icon(AppIcons.upload),
          title: Text(l10n.exportBackup),
          subtitle: Text(l10n.exportBackupSubtitle),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () => _showExport(context),
        ),
        ListTile(
          leading: const Icon(AppIcons.download),
          title: Text(l10n.importBackup),
          subtitle: Text(l10n.importBackupSubtitle),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () => _showImport(context),
        ),
        ListTile(
          leading: const Icon(AppIcons.box),
          title: Text(l10n.importAnki),
          subtitle: Text(l10n.importAnkiSubtitle),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () => _importAnki(context),
        ),
        ListTile(
          leading: const Icon(AppIcons.archive),
          title: Text(l10n.exportAnki),
          subtitle: Text(l10n.exportAnkiSubtitle),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () => _exportAnki(context),
        ),
        ListTile(
          leading: const Icon(AppIcons.history),
          title: Text(l10n.backupFiles),
          subtitle: Text(l10n.backupFilesSubtitle),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () => _showBackups(context),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(
            '${l10n.librarySummary(collections, cards, logs)}\n'
            '${l10n.dataFootnote}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportAnki(BuildContext context) async {
    final l10n = context.l10n;
    final decks = HiveService.getAllCollections();
    final scope = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.exportAnkiTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: ListTile(
              leading: const Icon(AppIcons.library),
              title: Text(l10n.scopeAllCollections),
            ),
          ),
          for (final deck in decks)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, deck.id),
              child: ListTile(
                leading: AppEmoji(deck.emoji, size: 20),
                title: Text(deck.name),
                subtitle: Text(l10n.cardCount(deck.cardCount)),
              ),
            ),
        ],
      ),
    );
    if (scope == null || !context.mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.exportAnkiQuestion,
      message: l10n.exportAnkiBody,
      confirmLabel: l10n.export,
      cancelLabel: l10n.cancel,
    );
    if (!confirmed || !context.mounted) return;
    try {
      final result = await const AnkiExportService().build(
        collectionId: scope.isEmpty ? null : scope,
      );
      if (!context.mounted) return;
      final save = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.ankiPackageReady),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.summary),
              const SizedBox(height: 8),
              if (result.warnings.isNotEmpty)
                InfoBanner(
                  icon: AppIcons.info,
                  message: result.warnings.take(3).join('\n'),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
            ],
          ),
          actions: [
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.close),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(AppIcons.save, size: 18),
                  label: Text(l10n.saveApkg),
                ),
              ],
            ),
          ],
        ),
      );
      if (save != true) return;
      final saved = await const AnkiExportService().saveAs(result);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved ? l10n.ankiPackageSaved : l10n.ankiPackageNotSaved,
          ),
        ),
      );
    } on AnkiExportException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.ankiExportFailed(error))));
    }
  }

  Future<void> _importAnki(BuildContext context) async {
    final l10n = context.l10n;
    try {
      final picked = await const AnkiImportService().pickPackage();
      if (picked == null || !context.mounted) return;
      final result = await showDialog<AnkiImportResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            AnkiImportDialog(bytes: picked.bytes, fileName: picked.fileName),
      );
      if (result == null || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.ankiImportSummary(result.summary))),
      );
    } on AnkiFormatException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.ankiImportFailed(error))));
    }
  }

  Future<void> _showExport(BuildContext context) async {
    final l10n = context.l10n;
    final json = BackupService.exportToJson();
    final cards = HiveService.getAllCards().length;
    final logs = HiveService.getAllLogs().length;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.exportBackupTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.librarySummary(
                  HiveService.getAllCollections().length,
                  cards,
                  logs,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    json.length > 1500 ? '${json.substring(0, 1500)}\n…' : json,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 11,
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
                child: Text(l10n.close),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: json));
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l10n.copyJsonDone)));
                },
                icon: const Icon(AppIcons.copy, size: 18),
                label: Text(l10n.copyJson),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final saved = await BackupService.saveBackupAs(json);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        saved ? l10n.backupSaved : l10n.backupNotSaved,
                      ),
                    ),
                  );
                },
                icon: const Icon(AppIcons.save, size: 18),
                label: Text(l10n.saveAs),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showImport(BuildContext context) async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    String? error;
    bool busy = false;
    ImportProgress? progress;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.importBackupTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (busy && progress != null) ...[
                    LinearProgressIndicator(value: progress!.fraction, minHeight: 4),
                    const SizedBox(height: 6),
                    Text(
                      '${progress!.stage} ${progress!.percentage}%',
                      style: Theme.of(dialogContext).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 12),
                  ] else if (busy) ...[
                    const LinearProgressIndicator(minHeight: 4),
                    const SizedBox(height: 12),
                  ],
                  Text(l10n.importBackupIntro),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final raw = await BackupService.pickBackupJson();
                              if (raw == null || !dialogContext.mounted) return;
                              controller.text = raw;
                              setState(() => error = null);
                            },
                      icon: const Icon(AppIcons.folderOpen, size: 18),
                      label: Text(l10n.chooseBackupFile),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    enabled: !busy,
                    minLines: 6,
                    maxLines: 12,
                    decoration: InputDecoration(
                      hintText: '{ "format": "knowit-backup", ... }',
                      errorText: error,
                      errorMaxLines: 3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  child: Text(l10n.cancel),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            final result = await BackupService.importJson(
                              controller.text,
                              onProgress: (p) => setState(() => progress = p),
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n.importedSummary(result.summary),
                                  ),
                                ),
                              );
                            }
                          } on FormatException catch (exception) {
                            setState(() {
                              error = exception.message;
                              busy = false;
                            });
                          } on Object catch (exception) {
                            setState(() {
                              error = l10n.importFailed(exception);
                              busy = false;
                            });
                          }
                        },
                  child: Text(busy ? l10n.importing : l10n.merge),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final confirmed = await showAppConfirmDialog(
                            dialogContext,
                            title: l10n.replaceAllData,
                            message: l10n.replaceAllDataBody,
                            confirmLabel: l10n.replace,
                            cancelLabel: l10n.cancel,
                            destructive: true,
                          );
                          if (!confirmed) return;
                          setState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            final result = await BackupService.importJson(
                              controller.text,
                              replace: true,
                              onProgress: (p) => setState(() => progress = p),
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n.restoredSummary(result.summary),
                                  ),
                                ),
                              );
                            }
                          } on FormatException catch (exception) {
                            setState(() {
                              error = exception.message;
                              busy = false;
                            });
                          } on Object catch (exception) {
                            setState(() {
                              error = l10n.importFailed(exception);
                              busy = false;
                            });
                          }
                        },
                  child: Text('${l10n.replace}…'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _showBackups(BuildContext context) async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.95,
        minChildSize: 0.35,
        builder: (sheetContext, sheetController) => StatefulBuilder(
          builder: (sheetContext, setState) {
            return FutureBuilder<List<BackupFileInfo>>(
              future: BackupService.listBackups(),
              builder: (context, snapshot) {
                final files = snapshot.data ?? const <BackupFileInfo>[];
                return ListView(
                  controller: sheetController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.backupFiles,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final file = await BackupService.writeBackupFile();
                            if (file != null) {
                              await BackupService.pruneOldBackups();
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    file == null
                                        ? l10n.savingUnavailable
                                        : l10n.backupSavedPath(file.path),
                                  ),
                                ),
                              );
                            }
                            setState(() {});
                          },
                          icon: const Icon(AppIcons.add, size: 18),
                          label: Text(l10n.newBackup),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(child: CircularProgressIndicator())
                    else if (files.isEmpty)
                      EmptyState(
                        icon: AppIcons.folderOpen,
                        title: l10n.noBackupFiles,
                        message: l10n.noBackupFilesMessage,
                        compact: true,
                      )
                    else
                      for (final file in files)
                        Card(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          child: ListTile(
                            leading: const Icon(AppIcons.documentText),
                            title: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${formatDate(file.modified)} · '
                              '${file.sizeLabel}',
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'delete') {
                                  await BackupService.deleteBackupFile(
                                    file.path,
                                  );
                                  setState(() {});
                                  return;
                                }
                                if (value != 'restore') return;
                                final confirmed = await showAppConfirmDialog(
                                  context,
                                  title: l10n.restoreBackupTitle,
                                  message: l10n.restoreBackupBody,
                                  confirmLabel: l10n.restoreLabel,
                                  cancelLabel: l10n.cancel,
                                  destructive: true,
                                );
                                if (!confirmed) return;
                                final raw = await BackupService.readBackupFile(
                                  file.path,
                                );
                                if (raw == null) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(l10n.couldNotReadBackup),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                try {
                                  if (!context.mounted) return;
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final result = await BackupService.importJson(
                                    raw,
                                    replace: true,
                                  );
                                  if (!context.mounted) return;
                                  Navigator.pop(sheetContext);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        l10n.restoredSummary(result.summary),
                                      ),
                                    ),
                                  );
                                } on Object catch (error) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.restoreFailed(error)),
                                    ),
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'restore',
                                  child: Text(l10n.restoreLabel),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(l10n.deleteFile),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _AiSection extends StatelessWidget {
  const _AiSection();

  Future<void> _testConnection(BuildContext context) async {
    final l10n = context.l10n;
    try {
      await AiService.testConnection();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.aiConnectionSucceeded)));
    } on AiProviderException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.aiConnectionFailed(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _SettingsCard(
      title: l10n.aiFeatures,
      children: [
        ListTile(
          leading: Icon(
            AiService.isConfigured ? AppIcons.sparkleFilled : AppIcons.sparkle,
            color: AiService.isConfigured ? theme.colorScheme.primary : null,
          ),
          title: Text(
            AiService.isConfigured ? AiService.providerName : l10n.noAiProvider,
          ),
          subtitle: Text(
            AiService.isConfigured
                ? l10n.aiConfiguredSubtitle
                : l10n.aiNotConfiguredSubtitle,
          ),
        ),
        if (!AiService.secureStorageAvailable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InfoBanner(
              icon: AppIcons.lock,
              message: l10n.secureStorageUnavailable,
              color: theme.colorScheme.error,
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  await showAiSettingsDialog(context);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                icon: const Icon(AppIcons.settings, size: 20),
                label: Text(
                  AiService.isConfigured
                      ? l10n.configureProvider
                      : l10n.configureAi,
                ),
              ),
              if (AiService.isConfigured) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _testConnection(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(AppIcons.cloudUpload, size: 20),
                  label: Text(l10n.testConnection),
                ),
              ],
            ],
          ),
        ),
        ListTile(
          leading: const Icon(AppIcons.sparkle),
          title: Text(l10n.generateWithAi),
          subtitle: Text(l10n.generateWithAiSubtitle),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiGenerateScreen()),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            l10n.aiKeyFootnote,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncSection extends StatelessWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final tombstones = TombstoneStore.all().length;
    return _SettingsCard(
      title: l10n.cloudSync,
      children: [
        ListTile(
          leading: const Icon(AppIcons.cloudOff),
          title: Text(l10n.noCloudBackend),
          subtitle: Text(l10n.syncFootnote(tombstones)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            l10n.syncFootnoteDetail,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  final String version;

  const _AboutSection({required this.version});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return _SettingsCard(
      title: l10n.about,
      children: [
        ListTile(
          leading: const Icon(AppIcons.bookOpen),
          title: Text(l10n.appTitle()),
          subtitle: Text(l10n.version(version)),
        ),
        ListTile(
          leading: const Icon(AppIcons.schedule),
          title: Text(l10n.spacedRepetition),
          subtitle: Text(l10n.spacedRepetitionSubtitle),
        ),
        ListTile(
          leading: const Icon(AppIcons.offline),
          title: Text(l10n.offlineFirst),
          subtitle: Text(l10n.offlineFirstSubtitle),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            l10n.aboutFootnote,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
