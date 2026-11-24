import 'dart:async';

import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/services/ai_service.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/notification_service.dart';
import 'package:knowit/services/settings_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await HiveService.init();
    await SettingsService.init();
    await AiService.init();
  } on Object catch (error) {
    runApp(_StartupErrorApp(error: error));
    return;
  }

  final settings = SettingsService.value;
  AppLocalizations.useLocale(settings.language.locale);
  if (settings.remindersEnabled) {
    unawaited(NotificationService.applySettings(settings));
  }

  runApp(const Knowit());
}

/// Shown only when the local database cannot be opened. No data is deleted
/// automatically; the message explains how to recover.
class _StartupErrorApp extends StatelessWidget {
  final Object error;

  const _StartupErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildKnowItTheme(Brightness.light),
      darkTheme: buildKnowItTheme(Brightness.dark),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    AppIcons.error,
                    size: 56,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    context.l10n.startupLibraryErrorTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.startupLibraryErrorBody,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    '$error',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
