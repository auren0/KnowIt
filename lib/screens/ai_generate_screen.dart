import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/screens/ai_settings_dialog.dart';
import 'package:knowit/services/ai/ai_prompt.dart';
import 'package:knowit/services/ai/duplicate_detector.dart';
import 'package:knowit/services/ai_service.dart';
import 'package:knowit/services/document_service.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/note_service.dart';
import 'package:knowit/services/settings_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/deck_tree.dart';
import 'package:knowit/utils/id_generator.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/empty_state.dart';
import 'package:knowit/widgets/insights.dart';
import 'package:knowit/widgets/rich_text.dart';
import 'package:knowit/widgets/selection_field.dart';

enum _SourceMode { text, document }

class AiGenerateScreen extends StatefulWidget {
  const AiGenerateScreen({super.key});

  @override
  State<AiGenerateScreen> createState() => _AiGenerateScreenState();
}

class _AiGenerateScreenState extends State<AiGenerateScreen> {
  static const List<String> _languages = [
    'Auto-detect',
    'English',
    'Spanish',
    'French',
    'German',
    'Portuguese',
    'Italian',
    'Dutch',
    'Polish',
    'Ukrainian',
    'Russian',
    'Turkish',
    'Arabic',
    'Hindi',
    'Chinese',
    'Japanese',
    'Korean',
  ];

  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();
  final DuplicateDetector _duplicates = const DuplicateDetector();

  _SourceMode _mode = _SourceMode.text;
  CardType _format = CardType.basic;
  int _cardCount = 10;
  String? _deckId;
  late String _sourceLanguage;
  late String _outputLanguage;
  DocumentExtractResult? _document;
  AiGenerationResult? _result;
  List<bool> _duplicateFlags = const [];
  Set<int> _selected = {};
  String? _error;
  List<String> _warnings = const [];
  String? _success;
  bool _generating = false;
  bool _extracting = false;
  bool _saving = false;
  AiCancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    final settings = SettingsService.value;
    _sourceLanguage = settings.aiSourceLanguage;
    _outputLanguage = settings.aiOutputLanguage;
    final decks = HiveService.getAllCollections();
    _deckId = decks.isEmpty ? null : decks.first.id;
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _sourceController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Collection? get _targetDeck {
    final id = _deckId;
    if (id == null) return null;
    return HiveService.getCollection(id);
  }

  Future<void> _openConfiguration() async {
    final configured = await showAiSettingsDialog(context);
    if (!mounted) return;
    if (configured) {
      setState(() {
        _error = null;
        _success = context.l10n.applyProviderConfigured;
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _pickDocument() async {
    setState(() {
      _extracting = true;
      _error = null;
    });
    try {
      final result = await const DocumentService().pickAndExtract(
        maxCharacters: maxAiSourceCharacters,
      );
      if (!mounted || result == null) return;
      setState(() {
        _document = result;
        _mode = _SourceMode.document;
        _sourceController.text = result.text;
        _warnings = result.warnings;
        _error = null;
      });
    } on DocumentExtractionException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '${context.l10n.couldNotExtractDocument} $error');
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _generate() async {
    final l10n = context.l10n;
    if (_generating) return;
    if (!AiService.isConfigured) {
      await _openConfiguration();
      return;
    }
    final deck = _targetDeck;
    if (deck == null) {
      setState(() => _error = context.l10n.chooseCollectionFirst);
      return;
    }
    var source = _sourceController.text.trim();
    if (source.isEmpty) {
      setState(() => _error = context.l10n.addSourceFirst);
      return;
    }
    final extraWarnings = <String>[];
    if (source.length > maxAiSourceCharacters) {
      source = source.substring(0, maxAiSourceCharacters);
      extraWarnings.add(l10n.truncatedSource(maxAiSourceCharacters));
    }

    final cancelToken = AiCancelToken();
    setState(() {
      _generating = true;
      _error = null;
      _success = null;
      _result = null;
      _duplicateFlags = const [];
      _selected = {};
      _warnings = _mode == _SourceMode.document && _document != null
          ? List<String>.from(_document!.warnings)
          : const [];
      _cancelToken = cancelToken;
    });

    try {
      final request = AiGenerationRequest(
        sourceText: source,
        topic: _topicController.text.trim(),
        cardCount: _cardCount,
        format: _format,
        sourceLanguage: _sourceLanguage,
        outputLanguage: _outputLanguage,
      );
      final result = await AiService.assistant.generateCards(
        request,
        cancelToken: cancelToken,
      );
      if (!mounted || cancelToken.isCancelled) return;
      final existing = HiveService.getCardsByCollection(deck.id);
      final flags = _duplicates.markDuplicates(
        generated: result.cards,
        existing: existing,
      );
      final duplicates = flags.where((flag) => flag).length;
      final warnings = <String>[...result.warnings, ...extraWarnings];
      if (duplicates > 0) {
        warnings.add(l10n.duplicatesWarning(duplicates));
      }
      setState(() {
        _result = result;
        _duplicateFlags = flags;
        _selected = {
          for (var index = 0; index < result.cards.length; index++)
            if (!flags[index]) index,
        };
        _warnings = warnings;
      });
    } on AiCancelledException {
      if (!mounted) return;
      setState(() => _error = l10n.aiGenerationCancelled);
    } on AiProviderException catch (exception) {
      if (!mounted) return;
      setState(() => _error = exception.message);
    } on Object catch (exception) {
      if (!mounted) return;
      setState(() => _error = l10n.aiGenerationFailed(exception));
    } finally {
      if (mounted) {
        setState(() {
          _generating = false;
          _cancelToken = null;
        });
      }
    }
  }

  void _refreshDuplicates({bool preserveSelection = true}) {
    final result = _result;
    final deck = _targetDeck;
    if (result == null || deck == null) return;
    final flags = _duplicates.markDuplicates(
      generated: result.cards,
      existing: HiveService.getCardsByCollection(deck.id),
    );
    setState(() {
      _duplicateFlags = flags;
      if (!preserveSelection) {
        _selected = {
          for (var index = 0; index < result.cards.length; index++)
            if (!flags[index]) index,
        };
      } else {
        _selected = _selected
            .where((index) => index < result.cards.length)
            .toSet();
        _selected.removeWhere((index) => flags[index]);
      }
    });
  }

  Future<void> _editGenerated(int index) async {
    final l10n = context.l10n;
    final result = _result;
    if (result == null) return;
    final card = result.cards[index];
    final frontController = TextEditingController(text: card.front);
    final backController = TextEditingController(text: card.back);
    final tagController = TextEditingController(text: card.tags.join(', '));
    String? error;
    final edited = await showDialog<AiGeneratedCard>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.editGeneratedCard),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: frontController,
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: _format == CardType.cloze
                          ? l10n.clozeText
                          : l10n.frontLabel,
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: backController,
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(labelText: l10n.backLabel),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tagController,
                    decoration: InputDecoration(
                      labelText: l10n.tagsCommaSeparated,
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
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final candidate = card.copyWith(
                      front: frontController.text.trim(),
                      back: backController.text.trim(),
                      tags: tagController.text
                          .split(',')
                          .map((tag) => tag.trim().toLowerCase())
                          .where((tag) => tag.isNotEmpty)
                          .toList(),
                    );
                    final validation = CardItem(
                      frontText: candidate.front,
                      backText: candidate.back,
                      collectionId: _deckId ?? '',
                      type: candidate.type,
                    ).validate();
                    if (validation != null) {
                      setState(() => error = validation);
                      return;
                    }
                    Navigator.pop(context, candidate);
                  },
                  child: Text(l10n.applyChanges),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    frontController.dispose();
    backController.dispose();
    tagController.dispose();
    if (edited == null || !mounted) return;
    final cards = List<AiGeneratedCard>.from(result.cards);
    cards[index] = edited;
    setState(() {
      _result = AiGenerationResult(cards: cards, warnings: _warnings);
    });
    _refreshDuplicates();
  }

  void _deleteGenerated(int index) {
    final result = _result;
    if (result == null) return;
    final cards = List<AiGeneratedCard>.from(result.cards)..removeAt(index);
    final selected = <int>{};
    for (final current in _selected) {
      if (current < index) selected.add(current);
      if (current > index) selected.add(current - 1);
    }
    setState(() {
      _result = cards.isEmpty
          ? null
          : AiGenerationResult(cards: cards, warnings: _warnings);
      _selected = selected;
    });
    _refreshDuplicates();
  }

  int get _plannedSiblingCount {
    final result = _result;
    if (result == null) return 0;
    const noteService = NoteService();
    return _selected.fold<int>(0, (sum, index) {
      final card = result.cards[index];
      return sum + noteService.specsFor(card.type, card.front).length;
    });
  }

  Future<void> _saveSelected() async {
    final l10n = context.l10n;
    final result = _result;
    final deck = _targetDeck;
    if (result == null || deck == null || _selected.isEmpty || _saving) return;
    final selectedCards = _selected
        .map((index) => result.cards[index])
        .toList();
    final planned = _plannedSiblingCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.saveCardsQuestion(planned, deck.name)),
        content: Text(l10n.saveCardsConfirm(selectedCards.length, planned)),
        actions: [
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.saveCards),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    var savedCards = 0;
    try {
      for (final card in selectedCards) {
        final plan = await HiveService.saveNote(
          CardItem(
            id: newId(),
            frontText: card.front,
            backText: card.back,
            collectionId: deck.id,
            type: card.type,
            tags: card.tags,
          ),
        );
        savedCards += plan.cards.length;
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _result = null;
        _selected = {};
        _duplicateFlags = const [];
        _success = l10n.savedCardsTo(savedCards, deck.name);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.savedThenFailed(savedCards, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        SettingsService.notifier,
        HiveService.collectionsListenable,
        HiveService.cardsListenable,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final l10n = context.l10n;
        final decks = HiveService.getAllCollections();
        final result = _result;
        final selectedDeck = _targetDeck;

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.aiFlashcards),
            actions: [
              IconButton(
                tooltip: AiService.isConfigured
                    ? l10n.aiProviderSettings
                    : l10n.configureAi,
                onPressed: _openConfiguration,
                icon: Icon(
                  AiService.isConfigured
                      ? AppIcons.sparkleFilled
                      : AppIcons.sparkle,
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              if (!AiService.isConfigured)
                Card(
                  color: theme.colorScheme.tertiaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              AppIcons.key,
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l10n.noAiProviderTitle,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.noAiProviderBody,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _openConfiguration,
                          icon: const Icon(AppIcons.settings, size: 18),
                          label: Text(l10n.configureAi),
                        ),
                      ],
                    ),
                  ),
                )
              else
                InfoBanner(
                  icon: AppIcons.cloudUpload,
                  message: l10n.usingProvider(AiService.providerName),
                ),
              const SizedBox(height: 18),
              SectionHeader(
                title: l10n.sourceContent,
                subtitle: l10n.sourceContentSubtitle,
              ),
              SegmentedButton<_SourceMode>(
                segments: [
                  ButtonSegment(
                    value: _SourceMode.text,
                    icon: const Icon(AppIcons.note, size: 18),
                    label: Text(l10n.text),
                  ),
                  ButtonSegment(
                    value: _SourceMode.document,
                    icon: const Icon(AppIcons.documentText, size: 18),
                    label: Text(l10n.document),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.first),
              ),
              if (_mode == _SourceMode.document) ...[
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              AppIcons.upload,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _document == null
                                    ? l10n.importPdfTxtMd
                                    : _document!.fileName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_document != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            l10n.extractedCharacters(
                              _document!.characters,
                              _document!.truncated,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _extracting ? null : _pickDocument,
                              icon: _extracting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(AppIcons.folderOpen, size: 18),
                              label: Text(
                                _extracting ? l10n.extracting : l10n.chooseFile,
                              ),
                            ),
                            if (_document != null)
                              TextButton(
                                onPressed: () => setState(() {
                                  _document = null;
                                  _sourceController.clear();
                                }),
                                child: Text(l10n.clear),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.filesStayLocal,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _sourceController,
                minLines: 7,
                maxLines: 16,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.studyNotes,
                  hintText: l10n.studyNotesHint,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _topicController,
                decoration: InputDecoration(
                  labelText: l10n.focusTopic,
                  hintText: l10n.focusTopicHint,
                ),
              ),
              const SizedBox(height: 20),
              SectionHeader(title: l10n.generationSettings),
              AppSelectField<String>(
                label: l10n.targetDeck,
                valueLabel: selectedDeck == null
                    ? ''
                    : deckLabelWithEmoji(decks, selectedDeck),
                value: _deckId,
                leadingIcon: AppIcons.folder,
                sheetTitle: l10n.targetDeck,
                searchable: decks.length > 8,
                options: [
                  for (final deck in decks)
                    AppSelectOption<String>(
                      value: deck.id,
                      label: deckLabelWithEmoji(decks, deck),
                      icon: AppIcons.folder,
                    ),
                ],
                onChanged: (value) {
                  setState(() => _deckId = value);
                  _refreshDuplicates(preserveSelection: false);
                },
              ),
              if (decks.isEmpty) ...[
                const SizedBox(height: 8),
                InfoBanner(
                  icon: AppIcons.info,
                  message: l10n.createCollectionFirst,
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(l10n.cardsToGenerate, style: theme.textTheme.bodyMedium),
                  const Spacer(),
                  Text(
                    '$_cardCount',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _cardCount.toDouble(),
                min: 1,
                max: 40,
                divisions: 39,
                label: '$_cardCount',
                onChanged: (value) =>
                    setState(() => _cardCount = value.round()),
              ),
              const SizedBox(height: 4),
              Text(l10n.format, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<CardType>(
                  segments: [
                    for (final type in CardType.values)
                      ButtonSegment(
                        value: type,
                        label: Text(l10n.cardTypeLabelOf(type)),
                      ),
                  ],
                  selected: {_format},
                  onSelectionChanged: (value) =>
                      setState(() => _format = value.first),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _format == CardType.basic
                    ? l10n.basicFormat
                    : _format == CardType.reversed
                    ? l10n.reversedFormat
                    : l10n.clozeFormat,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppSelectField<String>(
                      label: l10n.sourceLanguage,
                      valueLabel: _sourceLanguage,
                      value: _sourceLanguage,
                      leadingIcon: AppIcons.translate,
                      sheetTitle: l10n.sourceLanguage,
                      searchable: true,
                      options: [
                        for (final language in _languages)
                          AppSelectOption(
                            value: language,
                            label: language,
                            icon: AppIcons.translate,
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _sourceLanguage = value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppSelectField<String>(
                      label: l10n.outputLanguage,
                      valueLabel: _outputLanguage,
                      value: _outputLanguage,
                      leadingIcon: AppIcons.language,
                      sheetTitle: l10n.outputLanguage,
                      searchable: true,
                      options: [
                        for (final language in _languages.skip(1))
                          AppSelectOption(
                            value: language,
                            label: language,
                            icon: AppIcons.language,
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _outputLanguage = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_generating)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: null,
                        icon: const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        label: Text(l10n.generating),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _cancelToken?.cancel(),
                      child: Text(l10n.cancel),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        AiService.isConfigured &&
                            _sourceController.text.trim().isNotEmpty &&
                            selectedDeck != null
                        ? _generate
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(AppIcons.sparkle),
                    label: Text(
                      result == null ? l10n.generateCards : l10n.generateAgain,
                    ),
                  ),
                ),
              if (_success != null) ...[
                const SizedBox(height: 12),
                InfoBanner(icon: AppIcons.checkCircle, message: _success!),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                InfoBanner(
                  icon: AppIcons.error,
                  message: _error!,
                  color: theme.colorScheme.error,
                  trailing: AiService.isConfigured
                      ? TextButton(
                          onPressed: _generate,
                          child: Text(l10n.retryGeneration),
                        )
                      : null,
                ),
              ],
              if (result != null) ...[
                const SizedBox(height: 24),
                SectionHeader(
                  title: l10n.reviewGeneratedCards,
                  subtitle: l10n.generatedSummary(
                    result.cards.length,
                    _selected.length,
                    _plannedSiblingCount,
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      setState(() {
                        _selected = _selected.length == result.cards.length
                            ? {}
                            : {
                                for (
                                  var index = 0;
                                  index < result.cards.length;
                                  index++
                                )
                                  index,
                              };
                      });
                    },
                    child: Text(
                      _selected.length == result.cards.length
                          ? l10n.selectNone
                          : l10n.selectAll,
                    ),
                  ),
                ),
                if (_warnings.isNotEmpty) ...[
                  InfoBanner(
                    icon: AppIcons.info,
                    message: _warnings.join('\n'),
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(height: 8),
                ],
                for (var index = 0; index < result.cards.length; index++) ...[
                  _GeneratedCardTile(
                    card: result.cards[index],
                    selected: _selected.contains(index),
                    duplicate:
                        index < _duplicateFlags.length &&
                        _duplicateFlags[index],
                    onToggle: () {
                      setState(() {
                        if (!_selected.add(index)) _selected.remove(index);
                      });
                    },
                    onEdit: () => _editGenerated(index),
                    onDelete: () => _deleteGenerated(index),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selected.isEmpty || _saving
                        ? null
                        : _saveSelected,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(AppIcons.save),
                    label: Text(
                      _saving
                          ? l10n.save
                          : l10n.saveCountTo(
                              _plannedSiblingCount,
                              selectedDeck?.name ?? l10n.deck,
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _GeneratedCardTile extends StatelessWidget {
  final AiGeneratedCard card;
  final bool selected;
  final bool duplicate;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GeneratedCardTile({
    required this.card,
    required this.selected,
    required this.duplicate,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Card(
      color: selected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: selected, onChanged: (_) => onToggle()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatePill(
                          label: l10n.cardTypeLabelOf(card.type),
                          color: theme.colorScheme.primary,
                        ),
                        if (duplicate)
                          StatePill(
                            label: l10n.possibleDuplicate,
                            color: theme.colorScheme.error,
                          ),
                        for (final tag in card.tags)
                          StatePill(
                            label: '#$tag',
                            color: theme.colorScheme.tertiary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    MarkupText(
                      card.front,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    if (card.back.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      MarkupText(
                        card.back,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    tooltip: l10n.editGeneratedCard,
                    onPressed: onEdit,
                    icon: const Icon(AppIcons.edit, size: 19),
                  ),
                  IconButton(
                    tooltip: l10n.removeGeneratedCard,
                    onPressed: onDelete,
                    icon: Icon(
                      AppIcons.delete,
                      size: 19,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
