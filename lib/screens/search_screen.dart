import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
import 'package:knowit/widgets/app_emoji.dart';
import 'package:knowit/widgets/empty_state.dart';
import 'package:knowit/widgets/insights.dart';
import 'package:knowit/widgets/selection_field.dart';

enum SearchStateFilter { all, newCards, learning, review, due }

enum SearchDueFilter { any, today, week, overdue }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _deckId;
  SearchStateFilter _state = SearchStateFilter.all;
  SearchDueFilter _due = SearchDueFilter.any;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ({String text, String? tag}) _parseQuery(String raw) {
    final tokens = raw.split(RegExp(r'\s+')).where((token) => token.isNotEmpty);
    final textParts = <String>[];
    String? tag;
    for (final token in tokens) {
      if (token.startsWith('#') && token.length > 1) {
        tag = token.substring(1).toLowerCase();
      } else if (token.toLowerCase().startsWith('tag:')) {
        final value = token.substring(4);
        if (value.isNotEmpty) tag = value.toLowerCase();
      } else if (token.startsWith('is:') || token.startsWith('due:')) {
        // Handled by the filter chips and due parser.
      } else {
        textParts.add(token);
      }
    }
    return (text: textParts.join(' ').toLowerCase(), tag: tag);
  }

  SearchDueFilter _dueFromQuery(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('due:overdue')) return SearchDueFilter.overdue;
    if (lower.contains('due:today')) return SearchDueFilter.today;
    if (lower.contains('due:week')) return SearchDueFilter.week;
    return _due;
  }

  bool _matchesDue(CardItem card, SearchDueFilter filter) {
    final now = DateTime.now();
    switch (filter) {
      case SearchDueFilter.any:
        return true;
      case SearchDueFilter.overdue:
        return !card.isNew && card.due != null && card.due!.isBefore(now);
      case SearchDueFilter.today:
        return !card.isNew &&
            card.due != null &&
            !card.due!.isAfter(endOfDay(now));
      case SearchDueFilter.week:
        return !card.isNew &&
            card.due != null &&
            !card.due!.isAfter(endOfDay(now.add(const Duration(days: 7))));
    }
  }

  bool _matchesState(CardItem card, SearchStateFilter state) => switch (state) {
    SearchStateFilter.all => true,
    SearchStateFilter.newCards => card.isNew,
    SearchStateFilter.learning => card.isLearning || card.isRelearning,
    SearchStateFilter.review => card.isReview,
    SearchStateFilter.due => card.isDue(),
  };

  SearchStateFilter _stateFromQuery(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('is:new')) return SearchStateFilter.newCards;
    if (lower.contains('is:learning')) return SearchStateFilter.learning;
    if (lower.contains('is:review')) return SearchStateFilter.review;
    if (lower.contains('is:due')) return SearchStateFilter.due;
    return _state;
  }

  List<CardItem> _results(
    List<CardItem> cards,
    List<Collection> collections,
    ({String text, String? tag}) query,
    SearchDueFilter dueFilter,
    SearchStateFilter stateFilter,
  ) {
    final deckById = {for (final deck in collections) deck.id: deck};
    final scope = _deckId == null
        ? cards
        : HiveService.getCardsByCollection(_deckId!);
    final results =
        scope.where((card) {
          if (!_matchesState(card, stateFilter) ||
              !_matchesDue(card, dueFilter)) {
            return false;
          }
          if (query.tag != null &&
              !card.tags.any((tag) => tag.toLowerCase().contains(query.tag!))) {
            return false;
          }
          if (query.text.isEmpty) return true;
          final deck = deckById[card.collectionId];
          final deckName = deck == null
              ? ''
              : deckBreadcrumb(collections, deck).toLowerCase();
          return card.frontText.toLowerCase().contains(query.text) ||
              card.backText.toLowerCase().contains(query.text) ||
              card.tags.any((tag) => tag.toLowerCase().contains(query.text)) ||
              deckName.contains(query.text);
        }).toList()..sort((a, b) {
          final aDue = a.isDue() ? 0 : 1;
          final bDue = b.isDue() ? 0 : 1;
          if (aDue != bDue) return aDue.compareTo(bDue);
          return b.updatedAt.compareTo(a.updatedAt);
        });
    return results;
  }

  Future<void> _openCard(CardItem card) async {
    final result = await Navigator.push<CardEditorResult>(
      context,
      CupertinoPageRoute(
        builder: (_) =>
            CreateCardScreen(collectionId: card.collectionId, card: card),
      ),
    );
    if (!mounted || result == null) return;
    if (result.deleted) {
      final deleted = result.cards.isNotEmpty
          ? result.cards
          : [if (result.card != null) result.card!];
      if (deleted.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.cardDeleted),
            action: SnackBarAction(
              label: context.l10n.undo,
              onPressed: () => HiveService.restoreCards(deleted),
            ),
          ),
        );
      }
    }
  }

  Future<void> _studyResults(List<CardItem> results) async {
    if (results.isEmpty) return;
    await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        builder: (_) => StudyScreen(
          deckIds: results.map((card) => card.collectionId).toSet().toList(),
          title: context.l10n.searchResults,
          mode: StudyMode.quick,
          cards: results,
        ),
      ),
    );
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
        final theme = Theme.of(context);
        final collections = HiveService.getAllCollections();
        final cards = HiveService.getAllCards();
        final raw = _controller.text;
        final query = _parseQuery(raw);
        final dueFilter = _dueFromQuery(raw);
        final stateFilter = _stateFromQuery(raw);
        final results = _results(
          cards,
          collections,
          query,
          dueFilter,
          stateFilter,
        );
        final tags = <String>{
          for (final card in cards)
            for (final tag in card.tags) tag,
        }.toList()..sort();

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.browse),
            actions: [
              if (results.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _studyResults(results),
                  icon: const Icon(AppIcons.play, size: 18),
                  label: Text(l10n.studyResults(results.length)),
                ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: l10n.searchCardsDecksTags,
                    prefixIcon: const Icon(AppIcons.search),
                    suffixIcon: raw.isNotEmpty
                        ? IconButton(
                            tooltip: l10n.clearSearch,
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                            icon: const Icon(AppIcons.clear),
                          )
                        : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AppSelectField<String>(
                  label: l10n.collectionLabel,
                  dense: true,
                  valueLabel: _deckId == null
                      ? l10n.allCollections
                      : _deckLabel(collections, _deckId!),
                  value: _deckId ?? '',
                  leadingIcon: AppIcons.folder,
                  sheetTitle: l10n.collectionLabel,
                  searchable: collections.length > 8,
                  options: [
                    AppSelectOption<String>(
                      value: '',
                      label: l10n.allCollections,
                      icon: AppIcons.collections,
                    ),
                    for (final deck in collections)
                      AppSelectOption<String>(
                        value: deck.id,
                        label:
                            deckLabelWithEmoji(collections, deck),
                        icon: AppIcons.folder,
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _deckId = value.isEmpty ? null : value),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _stateChip(l10n.all, SearchStateFilter.all),
                    const SizedBox(width: 6),
                    _stateChip(l10n.newOnly, SearchStateFilter.newCards),
                    const SizedBox(width: 6),
                    _stateChip(l10n.learning, SearchStateFilter.learning),
                    const SizedBox(width: 6),
                    _stateChip(l10n.inReview, SearchStateFilter.review),
                    const SizedBox(width: 6),
                    _stateChip(l10n.dueNowFilter, SearchStateFilter.due),
                    if (dueFilter != SearchDueFilter.any) ...[
                      const SizedBox(width: 6),
                      InputChip(
                        label: Text(
                          dueFilter == SearchDueFilter.today
                              ? l10n.dueToday
                              : dueFilter == SearchDueFilter.week
                              ? l10n.dueThisWeek
                              : l10n.overdue,
                        ),
                        onDeleted: () {
                          final cleaned = raw
                              .replaceAll('due:today', '')
                              .replaceAll('due:week', '')
                              .replaceAll('due:overdue', '')
                              .trim();
                          _controller.text = cleaned;
                          setState(() => _due = SearchDueFilter.any);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              if (tags.isNotEmpty && raw.isEmpty) ...[
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        l10n.tags,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      for (final tag in tags.take(10))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text('#$tag'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              _controller.text = '#$tag';
                              _controller.selection = TextSelection.collapsed(
                                offset: _controller.text.length,
                              );
                              setState(() {});
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: raw.isEmpty && _state == SearchStateFilter.all
                    ? EmptyState(
                        icon: AppIcons.browse,
                        title: l10n.findAnythingTitle,
                        message: l10n.findAnythingMessage,
                        compact: true,
                      )
                    : results.isEmpty
                    ? EmptyState(
                        icon: AppIcons.search,
                        title: l10n.noMatchingCards,
                        message: l10n.noMatchingCardsMessage,
                        action: TextButton(
                          onPressed: () {
                            _controller.clear();
                            setState(() {
                              _state = SearchStateFilter.all;
                              _due = SearchDueFilter.any;
                              _deckId = null;
                            });
                          },
                          child: Text(l10n.resetSearch),
                        ),
                        compact: true,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final card = results[index];
                          final deck = HiveService.getCollection(
                            card.collectionId,
                          );
                          return _SearchResultTile(
                            card: card,
                            deck: deck,
                            onTap: () => _openCard(card),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _deckLabel(List<Collection> collections, String id) {
    final deck = collections.cast<Collection?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (deck == null) return id;
    return deckLabelWithEmoji(collections, deck);
  }

  Widget _stateChip(String label, SearchStateFilter state) {
    final queryState = _stateFromQuery(_controller.text);
    final selected = queryState == state;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        final cleaned = _controller.text
            .replaceAll(RegExp(r'is:\w+'), '')
            .trim();
        _controller.text = cleaned;
        setState(() => _state = state);
      },
      visualDensity: VisualDensity.compact,
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final CardItem card;
  final Collection? deck;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.card,
    required this.deck,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final stateColor = card.isNew
        ? theme.colorScheme.tertiary
        : card.isDue()
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppEmoji(deck?.emoji ?? '', size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      deck?.name ?? l10n.unknownCollection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
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
              const SizedBox(height: 8),
              Text(
                card.studyFront,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                card.studyBack,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (card.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (card.variantLabel != null)
                      StatePill(
                        label: card.variantLabel!,
                        color: theme.colorScheme.secondary,
                      ),
                    for (final tag in card.tags.take(4))
                      Text(
                        '#$tag',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
