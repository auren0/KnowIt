/// Small formatting helpers used across the app. Dates, times and numbers
/// follow the selected application locale.
library;

import 'package:intl/intl.dart';
import 'package:knowit/l10n/app_localizations.dart';

String _two(int value) => value.toString().padLeft(2, '0');

String get _localeName => AppLocalizations.current.locale.toLanguageTag();

/// Returns the start of the day in local time.
DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

/// Returns the last moment of the day in local time.
DateTime endOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

/// Returns the Monday of the week containing [date], in local time.
DateTime startOfWeek(DateTime date) {
  final day = startOfDay(date);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Stable local-time key used to group review logs by day.
String dayKey(DateTime date) =>
    '${date.year}-${_two(date.month)}-${_two(date.day)}';

String monthKey(DateTime date) => '${date.year}-${_two(date.month)}';

/// Localized short month names, kept for any callers that need the raw list.
List<String> get monthShortNames {
  final format = DateFormat.MMM(_localeName);
  return [
    for (var month = 1; month <= 12; month++)
      format.format(DateTime(2020, month)),
  ];
}

/// Localized weekday names, Monday first.
List<String> get weekdayShortNames {
  final format = DateFormat.E(_localeName);
  // 2020-01-06 was a Monday.
  return [
    for (var day = 0; day < 7; day++) format.format(DateTime(2020, 1, 6 + day)),
  ];
}

/// `12 Nov 2026` / `12 нояб. 2026 г.`
String formatDate(DateTime date) => DateFormat.yMMMd(_localeName).format(date);

/// `12 Nov` / `12 нояб.`
String formatDayMonth(DateTime date) =>
    DateFormat.MMMd(_localeName).format(date);

/// `08:30` / `8:30 PM`
String formatClock(int hour, int minute) =>
    DateFormat.Hm(_localeName).format(DateTime(2000, 1, 1, hour, minute));

/// `8:30 PM` / `20:30`
String formatTimeOfDayValue(int hour, int minute) =>
    DateFormat.jm(_localeName).format(DateTime(2000, 1, 1, hour, minute));

/// Human readable session/study duration: `42s`, `12m`, `1h 04m`.
String formatDuration(Duration duration) {
  final seconds = duration.inSeconds.abs();
  if (seconds < 60) return '${seconds}s';
  final minutes = duration.inMinutes;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return '${hours}h ${_two(rest)}m';
}

/// Human readable scheduling interval: `10m`, `3d`, `2mo`, `1.2y`.
String formatInterval(Duration duration) {
  if (duration.inMinutes < 1) {
    final seconds = duration.inSeconds;
    return seconds <= 1 ? '1s' : '${seconds}s';
  }
  if (duration.inHours < 1) return '${duration.inMinutes}m';
  if (duration.inDays < 1) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }
  final days = duration.inDays;
  if (days < 30) return '${days}d';
  if (days < 365) {
    final months = days / 30.0;
    return months < 10
        ? '${months.toStringAsFixed(1)}mo'
        : '${months.round()}mo';
  }
  final years = days / 365.0;
  return years < 10 ? '${years.toStringAsFixed(1)}y' : '${years.round()}y';
}

/// Relative due label used on deck cards and in search results.
String formatRelativeDue(DateTime due, {DateTime? now}) {
  final l10n = AppLocalizations.current;
  final current = now ?? DateTime.now();
  final difference = due.difference(current);
  if (difference.isNegative) return l10n.nowWord;
  if (difference.inMinutes < 1) return l10n.nowWord;
  if (difference.inMinutes < 60) {
    return l10n.relativeMinutes(difference.inMinutes);
  }
  if (difference.inHours < 24) return l10n.relativeHours(difference.inHours);
  if (difference.inDays < 30) return l10n.relativeDays(difference.inDays);
  return formatDayMonth(due);
}

/// `1 card` / `3 cards`. Prefer the locale-aware count helpers in
/// [AppLocalizations] for new code.
String pluralize(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';
