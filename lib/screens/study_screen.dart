import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fsrs/fsrs.dart' show Rating;
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/app_settings.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/scheduler_service.dart';
import 'package:knowit/services/settings_service.dart';
import 'package:knowit/services/study_queue_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/formatters.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/empty_state.dart';
import 'package:knowit/widgets/insights.dart';
import 'package:knowit/widgets/rich_text.dart';

class StudyScreen extends StatefulWidget {
  final List<String> deckIds;
  final String title;
  final StudyMode mode;
  final List<CardItem>? cards;

  const StudyScreen({
    super.key,
    required this.deckIds,
    required this.title,
    this.mode = StudyMode.srs,
    this.cards,
  });

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _UndoSnapshot {
  final List<CardItem> queue;
  final int index;
  final int completed;
  final bool revealed;
  final Map<int, int> ratings;
  final CardItem previousCard;
  final String logId;

  const _UndoSnapshot({
    required this.queue,
    required this.index,
    required this.completed,
    required this.revealed,
    required this.ratings,
    required this.previousCard,
    required this.logId,
  });
}

class _StudyScreenState extends State<StudyScreen>
    with SingleTickerProviderStateMixin {
  static const SchedulerService _scheduler = SchedulerService();

  final FocusNode _focusNode = FocusNode(debugLabel: 'study');
  late final AnimationController _flipController;

  List<CardItem> _queue = [];
  int _index = 0;
  int _completed = 0;
  bool _revealed = false;
  bool _loading = true;
  String? _error;
  DateTime _startedAt = DateTime.now();
  DateTime _cardShownAt = DateTime.now();
  Duration _sessionDuration = Duration.zero;
  Map<int, int> _ratings = {1: 0, 2: 0, 3: 0, 4: 0};
  Map<Rating, Duration> _previews = {};
  _UndoSnapshot? _undo;
  bool _hitNewLimit = false;
  bool _hitReviewLimit = false;
  bool _finishing = false;

  AppSettings get _settings => SettingsService.value;

  CardItem? get _current =>
      _queue.isEmpty || _index >= _queue.length ? null : _queue[_index];

  bool get _finished => !_loading && _error == null && _index >= _queue.length;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _load();
  }

  @override
  void dispose() {
    _flipController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _queue = [];
      _index = 0;
      _completed = 0;
      _ratings = {1: 0, 2: 0, 3: 0, 4: 0};
      _undo = null;
      _revealed = false;
      _startedAt = DateTime.now();
      _cardShownAt = DateTime.now();
    });

    try {
      final cards =
          widget.cards ?? HiveService.getCardsForCollections(widget.deckIds);
      final queue = const StudyQueueService().build(
        cards: cards,
        mode: widget.mode,
        settings: _settings,
        logs: widget.mode == StudyMode.difficult
            ? HiveService.getAllLogs()
            : HiveService.getTodayLogs(DateTime.now()),
      );
      if (!mounted) return;
      setState(() {
        _queue = queue.cards;
        _hitNewLimit = queue.hitNewLimit;
        _hitReviewLimit = queue.hitReviewLimit;
        _loading = false;
        _cardShownAt = DateTime.now();
        _previews = _current == null ? {} : _intervalsFor(_current!);
      });
      if (_current != null) _focusNode.requestFocus();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not prepare this study session.\n$error';
        _loading = false;
      });
    }
  }

  Map<Rating, Duration> _intervalsFor(CardItem card) {
    if (!widget.mode.changesSchedule) return const {};
    try {
      return _scheduler.previewIntervals(card: card, settings: _settings);
    } on Object {
      return const {};
    }
  }

  void _reveal() {
    if (_revealed || _current == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _revealed = true;
      _previews = _intervalsFor(_current!);
    });
    final animate =
        _settings.animationsEnabled &&
        _settings.answerRevealMode == AnswerRevealMode.flip &&
        !MediaQuery.of(context).disableAnimations;
    if (animate) {
      _flipController.forward();
    } else {
      _flipController.value = 1;
    }
    _focusNode.requestFocus();
  }

  Future<void> _rate(Rating rating) async {
    final card = _current;
    if (card == null || !_revealed || _finishing) return;
    _finishing = true;

    final previousQueue = List<CardItem>.from(_queue);
    final previousRatings = Map<int, int>.from(_ratings);
    final previousIndex = _index;
    final previousCompleted = _completed;
    final durationMs = DateTime.now().difference(_cardShownAt).inMilliseconds;

    try {
      final now = DateTime.now();
      late final String logId;

      if (widget.mode.changesSchedule) {
        final scheduled = _scheduler.schedule(
          card: card,
          rating: rating,
          settings: _settings,
          mode: widget.mode,
          now: now,
          durationMs: durationMs,
        );
        await HiveService.updateCard(scheduled.card);
        await HiveService.addLog(scheduled.log);
        logId = scheduled.log.id;

        // Re-show cards whose next step is minutes away, so learning steps are
        // actually rehearsed inside the current session.
        if (scheduled.card.due != null &&
            scheduled.card.due!.isBefore(
              now.add(const Duration(minutes: 10)),
            )) {
          _queue.add(scheduled.card);
        }
      } else {
        final log = _scheduler.practiceLog(
          card: card,
          rating: rating,
          mode: widget.mode,
          now: now,
          durationMs: durationMs,
        );
        await HiveService.addLog(log);
        logId = log.id;
      }

      if (!mounted) return;
      setState(() {
        _ratings = Map<int, int>.from(previousRatings);
        _ratings[rating.value] = (previousRatings[rating.value] ?? 0) + 1;
        _completed = previousCompleted + 1;
        _undo = _UndoSnapshot(
          queue: previousQueue,
          index: previousIndex,
          completed: previousCompleted,
          revealed: true,
          ratings: previousRatings,
          previousCard: card,
          logId: logId,
        );
        _index = previousIndex + 1;
        _revealed = false;
        _flipController.value = 0;
        _cardShownAt = DateTime.now();
        _previews = _current == null ? {} : _intervalsFor(_current!);
        if (_index >= _queue.length) {
          _sessionDuration = DateTime.now().difference(_startedAt);
        }
      });
      if (_settings.hapticFeedback) HapticFeedback.lightImpact();
      if (_current != null) _focusNode.requestFocus();
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(context.l10n.couldNotSaveReview(error), isError: true);
    } finally {
      _finishing = false;
    }
  }

  Future<void> _undoLast() async {
    final undo = _undo;
    if (undo == null) return;
    try {
      await HiveService.undoReview(undo.previousCard, undo.logId);
      if (!mounted) return;
      setState(() {
        _queue = undo.queue;
        _index = undo.index;
        _completed = undo.completed;
        _ratings = undo.ratings;
        _revealed = undo.revealed;
        _undo = null;
        _cardShownAt = DateTime.now();
        _previews = _current == null ? {} : _intervalsFor(_current!);
        _flipController.value = undo.revealed ? 1 : 0;
        _sessionDuration = DateTime.now().difference(_startedAt);
      });
      if (_settings.hapticFeedback) HapticFeedback.selectionClick();
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(context.l10n.couldNotUndo(error), isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? theme.colorScheme.error : null,
      ),
    );
  }

  Future<bool> _confirmExit() async {
    if (_completed == 0) return true;
    final l10n = context.l10n;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.endSessionTitle),
        content: Text(l10n.completedReviews(_completed)),
        actions: [
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.keepStudying),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.endSession),
              ),
            ],
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleClose() async {
    if (_finished) {
      Navigator.pop(context, _completed > 0);
      return;
    }
    if (await _confirmExit()) {
      if (!mounted) return;
      Navigator.pop(context, _completed > 0);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_settings.keyboardShortcuts || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
      if (_revealed) {
        _rate(Rating.good);
      } else {
        _reveal();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      if (_revealed) _rate(Rating.again);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      if (_revealed) _rate(Rating.hard);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      if (_revealed) _rate(Rating.good);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      if (_revealed) _rate(Rating.easy);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyU) {
      _undoLast();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _handleClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = math.max(_index + (_current == null ? 0 : 1), 1);
    final progress = _finished && _queue.isNotEmpty
        ? 1.0
        : _queue.isEmpty
        ? 0.0
        : (_index / math.max(_queue.length, 1)).clamp(0.0, 1.0);

    return PopScope(
      canPop: _finished || (_completed == 0 && _index == 0),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmExit()) {
          if (!context.mounted) return;
          Navigator.pop(context, _completed > 0);
        }
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: l10n.endSessionTooltip,
              icon: const Icon(AppIcons.close),
              onPressed: _handleClose,
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _loading
                      ? l10n.studyModeLabel(widget.mode)
                      : _finished
                      ? l10n.sessionComplete
                      : '${l10n.studyModeLabel(widget.mode)} · '
                            '${_index + 1} / $total',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: l10n.undoRatingTooltip,
                onPressed: _undo == null ? null : _undoLast,
                icon: const Icon(AppIcons.undo),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
          body: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = context.l10n;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: AppIcons.error,
        title: l10n.sessionCouldNotStart,
        message: _error!,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(AppIcons.refresh),
          label: Text(l10n.tryAgain),
        ),
      );
    }
    if (_finished) return _buildCompletion();
    final card = _current;
    if (card == null) return const SizedBox.shrink();

    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final flip =
        _settings.answerRevealMode == AnswerRevealMode.flip &&
        _settings.animationsEnabled &&
        !reducedMotion;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            if (!widget.mode.changesSchedule)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: InfoBanner(
                  icon: AppIcons.info,
                  message: l10n.practiceNoScheduleNote,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _StudyCard(
                      card: card,
                      revealed: _revealed,
                      flip: _flipController,
                      animateFlip: flip,
                      revealMode: _settings.answerRevealMode,
                      mode: widget.mode,
                      onReveal: _reveal,
                      onSwipe: (left) {
                        if (!_revealed || !_settings.swipeToRate) return;
                        _rate(left ? Rating.again : Rating.good);
                      },
                      retryLabel: _current == null
                          ? null
                          : _dueLabel(_current!),
                    ),
                  ),
                ),
              ),
            ),
            _buildControls(card),
          ],
        );
      },
    );
  }

  String? _dueLabel(CardItem card) {
    if (card.due == null || card.isNew) return null;
    return context.l10n.dueLabel(formatRelativeDue(card.due!).toLowerCase());
  }

  Widget _buildControls(CardItem card) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_revealed)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _reveal,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      icon: const Icon(AppIcons.eye),
                      label: Text(
                        l10n.showAnswer,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      _RatingButton(
                        label: l10n.again,
                        hint: '1',
                        interval: _intervalLabel(Rating.again),
                        tone: theme.colorScheme.error,
                        onTap: () => _rate(Rating.again),
                      ),
                      const SizedBox(width: 8),
                      _RatingButton(
                        label: l10n.hard,
                        hint: '2',
                        interval: _intervalLabel(Rating.hard),
                        tone: const Color(0xFFD08700),
                        onTap: () => _rate(Rating.hard),
                      ),
                      const SizedBox(width: 8),
                      _RatingButton(
                        label: l10n.good,
                        hint: '3',
                        interval: _intervalLabel(Rating.good),
                        tone: const Color(0xFF2E9E5B),
                        onTap: () => _rate(Rating.good),
                      ),
                      const SizedBox(width: 8),
                      _RatingButton(
                        label: l10n.easy,
                        hint: '4',
                        interval: _intervalLabel(Rating.easy),
                        tone: const Color(0xFF3A7BD5),
                        onTap: () => _rate(Rating.easy),
                      ),
                    ],
                  ),
                if (_settings.keyboardShortcuts) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.keyboardHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _intervalLabel(Rating rating) {
    if (!widget.mode.changesSchedule) {
      return context.l10n.practice.toLowerCase();
    }
    final interval = _previews[rating];
    return interval == null ? '' : formatInterval(interval);
  }

  Widget _buildCompletion() {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final totalRatings = _ratings.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final correct = totalRatings - (_ratings[1] ?? 0);
    final accuracy = totalRatings == 0 ? 0.0 : correct / totalRatings;
    final message = totalRatings == 0
        ? l10n.nothingDueQueue
        : accuracy >= 0.9
        ? l10n.outstandingRecall
        : accuracy >= 0.75
        ? l10n.solidSession
        : l10n.everyReviewCounts;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  AppIcons.check,
                  size: 44,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                totalRatings == 0
                    ? l10n.allCaughtUpTitle
                    : l10n.sessionComplete,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                color: theme.colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _CompletionStat(
                              value: '$totalRatings',
                              label: l10n.reviewsStat,
                            ),
                          ),
                          Expanded(
                            child: _CompletionStat(
                              value: formatDuration(_sessionDuration),
                              label: l10n.studyTime,
                            ),
                          ),
                          Expanded(
                            child: _CompletionStat(
                              value: totalRatings == 0
                                  ? '—'
                                  : '${(accuracy * 100).round()}%',
                              label: l10n.recallStat,
                            ),
                          ),
                        ],
                      ),
                      if (totalRatings > 0) ...[
                        const SizedBox(height: 18),
                        const Divider(),
                        const SizedBox(height: 14),
                        RatingBreakdown(counts: _ratings),
                      ],
                    ],
                  ),
                ),
              ),
              if (_hitNewLimit || _hitReviewLimit) ...[
                const SizedBox(height: 12),
                InfoBanner(
                  icon: AppIcons.options,
                  message: l10n.dailyLimitsNote,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(l10n.done),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(AppIcons.refresh),
                      label: Text(l10n.studyAgain),
                    ),
                  ),
                ],
              ),
              if (_completed > 0) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _undoLast(),
                  child: Text(l10n.undoLastRating),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletionStat extends StatelessWidget {
  final String value;
  final String label;

  const _CompletionStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StudyCard extends StatelessWidget {
  final CardItem card;
  final bool revealed;
  final AnimationController flip;
  final bool animateFlip;
  final AnswerRevealMode revealMode;
  final StudyMode mode;
  final VoidCallback onReveal;
  final ValueChanged<bool> onSwipe;
  final String? retryLabel;

  const _StudyCard({
    required this.card,
    required this.revealed,
    required this.flip,
    required this.animateFlip,
    required this.revealMode,
    required this.mode,
    required this.onReveal,
    required this.onSwipe,
    this.retryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInstant = revealMode == AnswerRevealMode.instant;

    final Widget cardBody;
    if (isInstant) {
      if (revealed) {
        cardBody = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: CardContent(card: card, showAnswer: false, showTags: true),
            ),
            const SizedBox(height: 18),
            Divider(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              thickness: 1,
            ),
            const SizedBox(height: 18),
            _AnswerSide(card: card, mode: mode),
          ],
        );
      } else {
        cardBody = _QuestionSide(card: card, hint: retryLabel);
      }
    } else {
      cardBody = revealed
          ? _AnswerSide(card: card, mode: mode)
          : _QuestionSide(card: card, hint: retryLabel);
    }

    final cardSurface = Card(
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 300),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: cardBody,
        ),
      ),
    );

    return GestureDetector(
      onTap: revealed ? null : onReveal,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -300) {
          onSwipe(true);
        } else if (velocity > 300) {
          onSwipe(false);
        }
      },
      child: (revealMode == AnswerRevealMode.flip && animateFlip)
          ? AnimatedBuilder(
              animation: flip,
              builder: (context, child) {
                final angle = flip.value * math.pi;
                final showBack = angle > math.pi / 2;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(angle),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: showBack
                        ? (Matrix4.identity()..rotateY(math.pi))
                        : Matrix4.identity(),
                    child: Card(
                      color: theme.colorScheme.surfaceContainerLow,
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 300),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: showBack
                              ? _AnswerSide(card: card, mode: mode)
                              : _QuestionSide(card: card, hint: retryLabel),
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          : cardSurface,
    );
  }
}

class _QuestionSide extends StatelessWidget {
  final CardItem card;
  final String? hint;

  const _QuestionSide({required this.card, this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: CardContent(card: card, showAnswer: false, showTags: true),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(
              AppIcons.tap,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              context.l10n.tapToReveal,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (hint != null)
              Text(
                hint!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AnswerSide extends StatelessWidget {
  final CardItem card;
  final StudyMode mode;

  const _AnswerSide({required this.card, required this.mode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.answer,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            const Spacer(),
            if (!mode.changesSchedule)
              StatePill(
                label: l10n.practice,
                color: theme.colorScheme.tertiary,
              ),
          ],
        ),
        const SizedBox(height: 12),
        CardContent(card: card, showAnswer: true, showTags: false),
        const SizedBox(height: 18),
        Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              AppIcons.info,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                card.variantLabel == null
                    ? l10n.cardTypeLabelOf(card.type)
                    : '${l10n.cardTypeLabelOf(card.type)} · '
                          '${card.reverse ? l10n.reversedVariant : l10n.clozeVariant(card.clozeIndex)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (card.reps > 0)
              Text(
                l10n.reviewedTimesShort(card.reps),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  final String label;
  final String interval;
  final String hint;
  final Color tone;
  final VoidCallback onTap;

  const _RatingButton({
    required this.label,
    required this.interval,
    required this.hint,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        button: true,
        label:
            '$label${interval.isEmpty ? '' : context.l10n.nextReviewIn(interval)}',
        child: Material(
          color: tone.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: tone.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hint,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tone.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    interval,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
