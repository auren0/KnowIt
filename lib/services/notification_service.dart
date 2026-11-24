import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Optional daily study reminders.
///
/// Notifications are created only when the user has enabled them. Failures are
/// swallowed and reported to the caller so the offline study experience can
/// never be blocked by a platform notification limitation.
class NotificationService {
  static const int reminderId = 42001;
  static const String channelId = 'study_reminders';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool _supported = true;

  static bool get isSupported => _supported && !kIsWeb;

  static Future<bool> _ensureInitialized() async {
    if (_initialized) return _supported;
    _initialized = true;
    if (kIsWeb) {
      _supported = false;
      return false;
    }
    try {
      tz_data.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } on Object {
        // Fall back to the timezone package default; reminders still use the
        // correct wall clock time in most cases.
      }

      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
          linux: const LinuxInitializationSettings(
            defaultActionName: 'Open KnowIt',
          ),
          windows: const WindowsInitializationSettings(
            appName: 'KnowIt',
            appUserModelId: 'KnowIt.KnowIt.Flutter',
            guid: 'b6f0c2d5-6f5a-4f0b-9d8b-2f5e3c1a7e42',
          ),
        ),
      );
      return true;
    } on Object {
      _supported = false;
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    if (!await _ensureInitialized()) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        final macos = _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        return await macos?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      return true;
    } on Object {
      return false;
    }
  }

  /// Applies the reminder settings. Returns true when the requested state was
  /// reached (scheduled or cancelled).
  static Future<bool> applySettings(AppSettings settings) async {
    if (!settings.remindersEnabled) {
      await cancel();
      return true;
    }
    if (!await _ensureInitialized()) return false;

    final granted = await requestPermission();
    if (!granted) return false;
    final l10n = AppLocalizations.current;

    try {
      final now = tz.TZDateTime.now(tz.local);
      var next = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        settings.reminderHour,
        settings.reminderMinute,
      );
      if (!next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
      }

      await _plugin.zonedSchedule(
        id: reminderId,
        title: l10n.notificationTitle,
        body: l10n.notificationBody,
        scheduledDate: next,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            l10n.notificationChannel,
            channelDescription: l10n.notificationChannelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(),
          macOS: const DarwinNotificationDetails(),
          linux: const LinuxNotificationDetails(),
          windows: const WindowsNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'study',
      );
      return true;
    } on Object {
      return false;
    }
  }

  static Future<void> cancel() async {
    if (!await _ensureInitialized()) return;
    try {
      await _plugin.cancel(id: reminderId);
    } on Object {
      // Nothing to cancel / unsupported platform.
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _supported = true;
  }
}
