import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/services/ai_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/empty_state.dart';

/// Shared provider configuration dialog used by Settings and the AI tab.
Future<bool> showAiSettingsDialog(BuildContext context) async {
  final l10n = context.l10n;
  final settings = AiService.settings;
  final baseController = TextEditingController(text: settings.aiBaseUrl);
  final modelController = TextEditingController(text: settings.aiModel);
  final keyController = TextEditingController();
  var busy = false;
  String? error;
  var obscureKey = true;

  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        Future<void> save({required bool test}) async {
          setState(() {
            busy = true;
            error = null;
          });
          try {
            await AiService.configure(
              providerId: 'openai-compatible',
              baseUrl: baseController.text,
              model: modelController.text,
              apiKey: keyController.text.trim().isEmpty
                  ? null
                  : keyController.text,
            );
            if (!AiService.hasStoredKey) {
              throw AiProviderException(l10n.enterApiKey);
            }
            if (test) {
              await AiService.testConnection();
            }
            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext, true);
          } on AiProviderException catch (exception) {
            setState(() {
              error = exception.message;
              busy = false;
            });
          } on Object catch (exception) {
            setState(() {
              error = l10n.couldNotSaveAi(exception);
              busy = false;
            });
          }
        }

        return AlertDialog(
          title: Text(l10n.configureAiTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.aiProviderIntro),
                  const SizedBox(height: 14),
                  TextField(
                    controller: baseController,
                    enabled: !busy,
                    decoration: InputDecoration(
                      labelText: l10n.baseUrl,
                      hintText: 'https://api.openai.com/v1',
                      prefixIcon: const Icon(AppIcons.key, size: 20),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: modelController,
                    enabled: !busy,
                    decoration: InputDecoration(
                      labelText: l10n.model,
                      hintText: 'e.g. gpt-4o-mini',
                      prefixIcon: const Icon(AppIcons.sparkle, size: 20),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: keyController,
                    enabled: !busy,
                    obscureText: obscureKey,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: AiService.hasStoredKey
                          ? l10n.replaceApiKey
                          : l10n.apiKey,
                      hintText: AiService.hasStoredKey
                          ? l10n.keyAlreadyStored
                          : 'sk-…',
                      prefixIcon: const Icon(AppIcons.lock, size: 20),
                      suffixIcon: IconButton(
                        tooltip: obscureKey ? l10n.showKey : l10n.hideKey,
                        onPressed: () =>
                            setState(() => obscureKey = !obscureKey),
                        icon: Icon(obscureKey ? AppIcons.eye : AppIcons.eyeOff),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InfoBanner(
                    icon: AppIcons.shield,
                    message: l10n.aiKeyWarning,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    InfoBanner(
                      icon: AppIcons.error,
                      message: error!,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final confirmed = await showAppConfirmDialog(
                            dialogContext,
                            title: l10n.removeAiConfiguration,
                            message: l10n.removeAiConfigurationBody,
                            confirmLabel: l10n.remove,
                            cancelLabel: l10n.cancel,
                            destructive: true,
                          );
                          if (!confirmed) return;
                          await AiService.clearConfiguration();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, false);
                          }
                        },
                  child: Text(l10n.remove),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: Text(l10n.cancel),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => save(test: true),
                  child: Text(busy ? l10n.testing : l10n.saveAndTest),
                ),
                FilledButton(
                  onPressed: busy ? null : () => save(test: false),
                  child: Text(l10n.save),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
  baseController.dispose();
  modelController.dispose();
  keyController.dispose();
  return changed ?? false;
}
