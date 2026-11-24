import 'dart:math';

/// Immutable snapshot of an ongoing import operation.
class ImportProgress {
  /// Progress from 0.0 to 1.0. Null indicates indeterminate progress.
  final double? fraction;

  /// High-level stage description (e.g. "Processing media files").
  final String stage;

  /// Optional detail counter (e.g. "(134 / 200)").
  final String? detail;

  /// Estimated time remaining, smoothed against noise.
  final Duration? eta;

  const ImportProgress({
    this.fraction,
    required this.stage,
    this.detail,
    this.eta,
  });

  bool get isIndeterminate => fraction == null;

  int get percentage =>
      fraction != null ? (fraction! * 100).clamp(0, 99).toInt() : 0;

  String formatEta({required bool isRussian}) {
    final remaining = eta;
    if (remaining == null) {
      return isRussian ? 'Вычисление…' : 'Calculating…';
    }
    final seconds = remaining.inSeconds;
    if (seconds <= 2) {
      return isRussian
          ? 'Осталось несколько секунд'
          : 'A few seconds remaining';
    }
    if (seconds < 60) {
      return isRussian
          ? 'Осталось примерно $seconds сек.'
          : 'Approximately $seconds seconds remaining';
    }
    final minutes = (seconds / 60).ceil();
    return isRussian
        ? 'Осталось примерно $minutes мин.'
        : 'Approximately $minutes minutes remaining';
  }
}

/// Token used to signal and check cancellation for long-running imports.
class ImportCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw const ImportCancelledException();
    }
  }
}

class ImportCancelledException implements Exception {
  final String message;

  const ImportCancelledException([this.message = 'Import was cancelled.']);

  @override
  String toString() => message;
}

/// Smoothly estimates remaining time based on observed processing speed.
class EtaEstimator {
  final DateTime _startTime = DateTime.now();
  double? _smoothedRemainingSeconds;

  Duration? update(double? currentFraction) {
    if (currentFraction == null || currentFraction <= 0.02) {
      return null;
    }
    if (currentFraction >= 1.0) {
      return Duration.zero;
    }

    final elapsedMs = DateTime.now().difference(_startTime).inMilliseconds;
    if (elapsedMs < 400) {
      return null;
    }

    final elapsedSeconds = elapsedMs / 1000.0;
    final rate = currentFraction / elapsedSeconds;
    if (rate <= 0) return null;

    final remainingFraction = 1.0 - currentFraction;
    final rawSeconds = remainingFraction / rate;

    final smoothed = _smoothedRemainingSeconds == null
        ? rawSeconds
        : (_smoothedRemainingSeconds! * 0.75 + rawSeconds * 0.25);
    _smoothedRemainingSeconds = smoothed;

    return Duration(seconds: max(1, smoothed.round()));
  }
}

/// Throttles progress notifications to prevent flooding UI thread with rebuilds.
/// Guarantees that stage transitions, initial/final states, and throttled updates
/// (e.g. >= 60ms interval) are emitted reliably.
class ProgressThrottler {
  final Duration interval;
  final void Function(ImportProgress progress)? onProgress;
  final EtaEstimator _eta = EtaEstimator();

  DateTime _lastEmitTime = DateTime.fromMillisecondsSinceEpoch(0);
  double? _lastFraction;
  String? _lastStage;

  ProgressThrottler({
    this.onProgress,
    this.interval = const Duration(milliseconds: 60),
  });

  void report(double? fraction, String stage, [String? detail]) {
    if (onProgress == null) return;

    final now = DateTime.now();
    final isStageChange = stage != _lastStage;
    final isComplete = fraction != null && fraction >= 1.0;
    final isInitial = _lastFraction == null;
    final elapsed = now.difference(_lastEmitTime);

    if (isStageChange || isComplete || isInitial || elapsed >= interval) {
      _lastEmitTime = now;
      _lastFraction = fraction;
      _lastStage = stage;
      onProgress!(
        ImportProgress(
          fraction: fraction,
          stage: stage,
          detail: detail,
          eta: _eta.update(fraction),
        ),
      );
    }
  }

  void flush(double? fraction, String stage, [String? detail]) {
    if (onProgress == null) return;
    _lastEmitTime = DateTime.now();
    _lastFraction = fraction;
    _lastStage = stage;
    onProgress!(
      ImportProgress(
        fraction: fraction,
        stage: stage,
        detail: detail,
        eta: _eta.update(fraction),
      ),
    );
  }
}
