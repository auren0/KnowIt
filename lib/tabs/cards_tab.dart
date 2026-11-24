import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/models/study_mode.dart';
import 'package:knowit/screens/create_card_screen.dart';
import 'package:knowit/screens/study_screen.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/deck_tree.dart';
import 'package:knowit/utils/formatters.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/app_emoji.dart';
import 'package:knowit/widgets/empty_state.dart';
import 'package:knowit/widgets/insights.dart';
import 'package:knowit/widgets/rich_text.dart';

enum CardSort { newest, oldest, alphabetical, dueDate, state }

enum CardStateFilter { all, newCards, learning, review, due, withMedia }

class CardsTab extends StatefulWidget {
  final String collectionId;

  const CardsTab({super.key, required this.collectionId});

  @override
  State<CardsTab> createState() => _CardsTabState();
}

class _CardsTabState extends State<CardsTab> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = {};
  CardSort _sort = CardSort.newest;
  CardStateFilter _filter = CardStateFilter.all;
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CardItem> _visibleCards([List<CardItem>? sourceCards]) {
    final query = _searchController.text.trim().toLowerCase();
    final cards =
        sourceCards ?? HiveService.getCardsByCollection(widget.collectionId);
    final filtered = cards.where((card) {
      if (!_matchesState(card)) return false;
      if (query.isEmpty) return true;
      return card.frontText.toLowerCase().contains(query) ||
          card.backText.toLowerCase().contains(query) ||
          card.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();

    int compare(CardItem a, CardItem b) {
      switch (_sort) {
        case CardSort.newest:
          return b.createdAt.compareTo(a.createdAt);
        case CardSort.oldest:
          return a.createdAt.compareTo(b.createdAt);
        case CardSort.alphabetical:
          return a.frontText.toLowerCase().compareTo(b.frontText.toLowerCase());
        case CardSort.dueDate:
          final aDue = a.due ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDue = b.due ?? DateTime.fromMillisecondsSinceEpoch(0);
          return aDue.compareTo(bDue);
        case CardSort.state:
          final state = a.state.index.compareTo(b.state.index);
          if (state != 0) return state;
          return a.frontText.toLowerCase().compareTo(b.frontText.toLowerCase());
      }
    }

    filtered.sort(compare);
    return filtered;
  }

  bool _matchesState(CardItem card) {
    switch (_filter) {
      case CardStateFilter.all:
        return true;
      case CardStateFilter.newCards:
        return card.isNew;
      case CardStateFilter.learning:
        return card.isLearning || card.isRelearning;
      case CardStateFilter.review:
        return card.isReview;
      case CardStateFilter.due:
        return card.isDue();
      case CardStateFilter.withMedia:
        return card.hasImage || card.isPlayable;
    }
  }

  void _toggleSelection(CardItem card) {
    setState(() {
      if (!_selectionMode) {
        _selectionMode = true;
        _selectedIds
          ..clear()
          ..add(card.id);
      } else if (_selectedIds.contains(card.id)) {
        _selectedIds.remove(card.id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(card.id);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _showUndoDelete(List<CardItem> deleted) {
    if (deleted.isEmpty) return;
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted.length == 1
              ? l10n.cardDeleted
              : l10n.cardsDeleted(deleted.length),
        ),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () async {
            await HiveService.restoreCards(deleted);
          },
        ),
      ),
    );
  }

  Future<void> _deleteCards(List<CardItem> cards) async {
    if (cards.isEmpty) return;
    final l10n = context.l10n;
    final confirmed = cards.length == 1
        ? true
        : await showAppConfirmDialog(
            context,
            title: l10n.deleteCardsTitleCount(cards.length),
            message: l10n.deleteCardsBody,
            confirmLabel: l10n.delete,
            cancelLabel: l10n.cancel,
            destructive: true,
          );
    if (!confirmed) return;
    final deleted = await HiveService.deleteCards(cards.map((card) => card.id));
    if (!mounted) return;
    _exitSelection();
    _showUndoDelete(deleted);
  }

  Future<void> _duplicateCards(List<CardItem> cards) async {
    final copies = await HiveService.duplicateCards(
      cards.map((card) => card.id),
    );
    if (!mounted) return;
    _exitSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copies.length == 1
              ? context.l10n.noteDuplicated
              : context.l10n.cardsDuplicated(copies.length),
        ),
      ),
    );
  }

  Future<void> _moveCards(List<CardItem> cards) async {
    if (cards.isEmpty) return;
    final l10n = context.l10n;
    final collections = HiveService.getAllCollections();
    final targets = collections
        .where((deck) => deck.id != widget.collectionId)
        .toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.createAnotherCollection)));
      return;
    }
    final target = await showDialog<Collection>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
          cards.length == 1
              ? l10n.moveCardTo('')
              : l10n.moveCardsTo(cards.length),
        ),
        children: [
          for (final deck in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, deck),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: AppEmoji(deck.emoji, size: 20),
                title: Text(deckBreadcrumb(collections, deck)),
                subtitle: Text(l10n.cardCount(deck.cardCount)),
              ),
            ),
        ],
      ),
    );
    if (target == null) return;
    await HiveService.moveCards(cards.map((card) => card.id), target.id);
    if (!mounted) return;
    _exitSelection();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.movedTo(target.name))));
  }

  Future<void> _editCard(CardItem card) async {
    final result = await Navigator.push<CardEditorResult>(
      context,
      CupertinoPageRoute(
        builder: (_) =>
            CreateCardScreen(collectionId: card.collectionId, card: card),
      ),
    );
    if (!mounted || result == null) return;
    if (result.deleted) {
      _showUndoDelete(
        result.cards.isNotEmpty
            ? result.cards
            : [if (result.card != null) result.card!],
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.cardSaved)));
    }
  }

  Future<void> _addCard() async {
    final result = await Navigator.push<CardEditorResult>(
      context,
      CupertinoPageRoute(
        builder: (_) => CreateCardScreen(collectionId: widget.collectionId),
      ),
    );
    if (!mounted || result?.card == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.cardCreated)));
  }

  void _showPreview(CardItem card) {
    final l10n = context.l10n;
    final collections = HiveService.getAllCollections();
    final deck = HiveService.getCollection(card.collectionId);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      deck == null
                          ? l10n.cardPreview
                          : deckLabelWithEmoji(collections, deck),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  StatePill(
                    label: l10n.learningStateLabel(card.state.index),
                    color: card.isNew
                        ? theme.colorScheme.tertiary
                        : card.isDue()
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                l10n.front,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              CardContent(card: card, showAnswer: false, showTags: true),
              const Divider(height: 30),
              Text(
                l10n.back,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              CardContent(card: card, showAnswer: true, showTags: false),
              const SizedBox(height: 20),
              Text(
                _scheduleSummary(card),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push<bool>(
                        this.context,
                        CupertinoPageRoute(
                          builder: (_) => StudyScreen(
                            deckIds: [card.collectionId],
                            title: deck?.name ?? l10n.cardPreview,
                            mode: StudyMode.quick,
                            cards: [card],
                          ),
                        ),
                      );
                    },
                    icon: const Icon(AppIcons.quick, size: 18),
                    label: Text(l10n.quickPractice),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _editCard(card);
                    },
                    icon: const Icon(AppIcons.edit, size: 18),
                    label: Text(l10n.edit),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _duplicateCards([card]);
                    },
                    icon: const Icon(AppIcons.copy, size: 18),
                    label: Text(l10n.duplicate),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _moveCards([card]);
                    },
                    icon: const Icon(AppIcons.move, size: 18),
                    label: Text(l10n.move),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteCards([card]);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    icon: const Icon(AppIcons.delete, size: 18),
                    label: Text(l10n.delete),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _scheduleSummary(CardItem card) {
    final l10n = context.l10n;
    if (card.isNew) return l10n.noCardsYet;
    final due = card.due == null
        ? l10n.unscheduled
        : formatRelativeDue(card.due!);
    final stability = card.stability == null
        ? '—'
        : '${card.stability!.toStringAsFixed(1)}d';
    return '${l10n.learningStateLabel(card.state.index)} · '
        '${l10n.dueLabel(due)} · ${l10n.reviewedTimesShort(card.reps)} · '
        '${l10n.lapsesLabel(card.lapses)} · '
        '${l10n.stabilityLabel(stability)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedBuilder(
      animation: Listenable.merge([
        HiveService.cardsListenable,
        HiveService.collectionsListenable,
      ]),
      builder: (context, _) {
        final allCards = HiveService.getCardsByCollection(widget.collectionId);
        final visible = _visibleCards(allCards);
        final theme = Theme.of(context);

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
                child: Row(
                  children: [
                    if (_selectionMode) ...[
                      IconButton(
                        tooltip: l10n.exitSelection,
                        onPressed: _exitSelection,
                        icon: const Icon(AppIcons.close),
                      ),
                      Text(
                        l10n.selectedCount(_selectedIds.length),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_selectedIds.length == visible.length) {
                              _selectedIds.clear();
                            } else {
                              _selectedIds
                                ..clear()
                                ..addAll(visible.map((card) => card.id));
                            }
                          });
                        },
                        child: Text(
                          _selectedIds.length == visible.length
                              ? l10n.clearAll
                              : l10n.selectAll,
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: l10n.searchCardsAndTags,
                            prefixIcon: const Icon(AppIcons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    tooltip: l10n.clearSearch,
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(AppIcons.clear),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<CardSort>(
                        tooltip: l10n.sortCards,
                        icon: Icon(
                          AppIcons.sort,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onSelected: (value) => setState(() => _sort = value),
                        itemBuilder: (context) => [
                          for (final option in CardSort.values)
                            CheckedPopupMenuItem(
                              value: option,
                              checked: _sort == option,
                              child: Text(_sortLabel(l10n, option)),
                            ),
                        ],
                      ),
                      PopupMenuButton<CardStateFilter>(
                        tooltip: l10n.filterCards,
                        icon: Icon(
                          AppIcons.filter,
                          color: _filter == CardStateFilter.all
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.primary,
                        ),
                        onSelected: (value) => setState(() => _filter = value),
                        itemBuilder: (context) => [
                          for (final option in CardStateFilter.values)
                            CheckedPopupMenuItem(
                              value: option,
                              checked: _filter == option,
                              child: Text(_filterLabel(l10n, option)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                children: [
                  Text(
                    l10n.summaryLine(visible.length, allCards.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (_filter != CardStateFilter.all)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: InputChip(
                        label: Text(_filterLabel(l10n, _filter)),
                        onDeleted: () =>
                            setState(() => _filter = CardStateFilter.all),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  if (_sort != CardSort.newest)
                    InputChip(
                      label: Text(_sortLabel(l10n, _sort)),
                      onDeleted: () => setState(() => _sort = CardSort.newest),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: allCards.isEmpty
                            ? AppIcons.card
                            : AppIcons.search,
                        title: allCards.isEmpty
                            ? l10n.noCardsYet
                            : l10n.noMatchingCards,
                        message: allCards.isEmpty
                            ? l10n.noCardsMessage
                            : l10n.tryDifferentSearch,
                        action: allCards.isEmpty
                            ? FilledButton.icon(
                                onPressed: _addCard,
                                icon: const Icon(AppIcons.add),
                                label: Text(l10n.addCard),
                              )
                            : TextButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _filter = CardStateFilter.all);
                                },
                                child: Text(l10n.clearFilters),
                              ),
                        compact: true,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final card = visible[index];
                          final selected = _selectedIds.contains(card.id);
                          final tile = _CardTile(
                            card: card,
                            selected: selected,
                            selectionMode: _selectionMode,
                            onTap: () {
                              if (_selectionMode) {
                                _toggleSelection(card);
                              } else {
                                _showPreview(card);
                              }
                            },
                            onLongPress: () => _toggleSelection(card),
                            onToggleSelected: () => _toggleSelection(card),
                          );
                          if (_selectionMode) return tile;
                          return Slidable(
                            key: ValueKey(card.id),
                            endActionPane: ActionPane(
                              motion: const StretchMotion(),
                              extentRatio: 0.42,
                              children: [
                                SlidableAction(
                                  borderRadius: BorderRadius.circular(16),
                                  onPressed: (_) => _editCard(card),
                                  icon: AppIcons.edit,
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  label: l10n.edit,
                                ),
                                SlidableAction(
                                  borderRadius: BorderRadius.circular(16),
                                  onPressed: (_) => _deleteCards([card]),
                                  icon: AppIcons.delete,
                                  backgroundColor: theme.colorScheme.error,
                                  foregroundColor: theme.colorScheme.onError,
                                  label: l10n.delete,
                                ),
                              ],
                            ),
                            child: tile,
                          );
                        },
                      ),
              ),
              if (_selectionMode)
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _BulkAction(
                            icon: AppIcons.delete,
                            label: l10n.delete,
                            onPressed: _selectedIds.isEmpty
                                ? null
                                : () => _deleteCards(
                                    allCards
                                        .where(
                                          (card) =>
                                              _selectedIds.contains(card.id),
                                        )
                                        .toList(),
                                  ),
                          ),
                        ),
                        Expanded(
                          child: _BulkAction(
                            icon: AppIcons.move,
                            label: l10n.move,
                            onPressed: _selectedIds.isEmpty
                                ? null
                                : () => _moveCards(
                                    allCards
                                        .where(
                                          (card) =>
                                              _selectedIds.contains(card.id),
                                        )
                                        .toList(),
                                  ),
                          ),
                        ),
                        Expanded(
                          child: _BulkAction(
                            icon: AppIcons.copy,
                            label: l10n.duplicate,
                            onPressed: _selectedIds.isEmpty
                                ? null
                                : () => _duplicateCards(
                                    allCards
                                        .where(
                                          (card) =>
                                              _selectedIds.contains(card.id),
                                        )
                                        .toList(),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          floatingActionButton: _selectionMode
              ? null
              : FloatingActionButton(
                  tooltip: l10n.addCard,
                  onPressed: _addCard,
                  child: const Icon(AppIcons.addCircle),
                ),
        );
      },
    );
  }

  static String _sortLabel(AppLocalizations l10n, CardSort sort) =>
      switch (sort) {
        CardSort.newest => l10n.newestFirst,
        CardSort.oldest => l10n.oldestFirst,
        CardSort.alphabetical => l10n.alphabetical,
        CardSort.dueDate => l10n.dueDate,
        CardSort.state => l10n.learningState,
      };

  static String _filterLabel(AppLocalizations l10n, CardStateFilter filter) =>
      switch (filter) {
        CardStateFilter.all => l10n.allCards,
        CardStateFilter.newCards => l10n.newOnly,
        CardStateFilter.learning => l10n.learning,
        CardStateFilter.review => l10n.inReviewFilter,
        CardStateFilter.due => l10n.dueNowFilter,
        CardStateFilter.withMedia => l10n.withMedia,
      };
}

class _CardTile extends StatelessWidget {
  final CardItem card;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelected;

  const _CardTile({
    required this.card,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final stateColor = card.isNew
        ? theme.colorScheme.tertiary
        : card.isDue()
        ? theme.colorScheme.error
        : card.isLearning || card.isRelearning
        ? const Color(0xFFD08700)
        : theme.colorScheme.primary;

    return Card(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: selectionMode ? onToggleSelected : onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode) ...[
                Checkbox(
                  value: selected,
                  onChanged: (_) => onToggleSelected(),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            card.studyFront,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatePill(
                          label: card.isNew
                              ? l10n.newOnly
                              : card.isDue()
                              ? l10n.dueBadge
                              : l10n.learningStateLabel(card.state.index),
                          color: stateColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.studyBack,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (card.tags.isNotEmpty)
                          for (final tag in card.tags.take(3))
                            Text(
                              '#$tag',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                        if (card.hasImage)
                          Icon(
                            AppIcons.image,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        if (card.isPlayable)
                          Icon(
                            AppIcons.audio,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        if (card.type != CardType.basic)
                          Icon(
                            card.type == CardType.cloze
                                ? AppIcons.cloze
                                : AppIcons.reversed,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        if (card.variantLabel != null)
                          StatePill(
                            label: card.reverse
                                ? l10n.reversedVariant
                                : l10n.clozeVariant(card.clozeIndex),
                            color: theme.colorScheme.secondary,
                          ),
                        Text(
                          card.isNew
                              ? l10n.notStudied
                              : card.due == null
                              ? l10n.unscheduled
                              : l10n.dueLabel(
                                  formatRelativeDue(card.due!).toLowerCase(),
                                ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _BulkAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.labelSmall, maxLines: 1),
        ],
      ),
    );
  }
}
