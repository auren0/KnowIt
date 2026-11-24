import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/card_item.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/media_service.dart';
import 'package:knowit/services/note_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/deck_tree.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/app_emoji.dart';
import 'package:knowit/widgets/empty_state.dart';
import 'package:knowit/widgets/insights.dart';
import 'package:knowit/widgets/rich_text.dart';
import 'package:knowit/widgets/selection_field.dart';

class CardEditorResult {
  final CardItem? card;
  final List<CardItem> cards;
  final bool deleted;

  const CardEditorResult({
    this.card,
    this.cards = const [],
    this.deleted = false,
  });
}

/// Distraction-free card editor with formatting, tags, media attachments,
/// deck selection and a live preview. Works for new and existing cards.
class CreateCardScreen extends StatefulWidget {
  final String collectionId;
  final CardItem? card;

  const CreateCardScreen({super.key, required this.collectionId, this.card});

  @override
  State<CreateCardScreen> createState() => _CreateCardScreenState();
}

class _CreateCardScreenState extends State<CreateCardScreen> {
  late final TextEditingController _frontController;
  late final TextEditingController _backController;
  final TextEditingController _tagController = TextEditingController();
  final FocusNode _frontFocus = FocusNode(debugLabel: 'front');
  final FocusNode _tagFocus = FocusNode(debugLabel: 'tag');

  late CardType _type;
  late String _collectionId;
  late List<String> _tags;
  String? _imagePath;
  String? _audioPath;
  String? _error;
  bool _saving = false;
  bool _dirty = false;
  bool _previewBack = false;

  bool get _isEditing => widget.card != null;

  @override
  void initState() {
    super.initState();
    final card = widget.card;
    _frontController = TextEditingController(text: card?.frontText ?? '')
      ..addListener(_markDirty);
    _backController = TextEditingController(text: card?.backText ?? '')
      ..addListener(_markDirty);
    _type = card?.type ?? CardType.basic;
    _collectionId = card?.collectionId ?? widget.collectionId;
    _tags = List<String>.from(card?.tags ?? const []);
    _imagePath = card?.imagePath;
    _audioPath = card?.audioPath;
    if (!_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _frontFocus.requestFocus();
      });
    }
  }

  void _markDirty() {
    if (!mounted) return;
    if (!_dirty) {
      setState(() => _dirty = true);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _frontController.dispose();
    _backController.dispose();
    _tagController.dispose();
    _frontFocus.dispose();
    _tagFocus.dispose();
    super.dispose();
  }

  List<Collection> get _decks {
    final decks = HiveService.getAllCollections();
    // Ensure the current deck exists in the dropdown even if it was deleted
    // concurrently; the UI will surface a clear error on save.
    return decks;
  }

  CardItem _draftCard({String? id}) {
    final base = widget.card;
    final specs = const NoteService().specsFor(_type, _frontController.text);
    var clozeIndex = 0;
    if (_type == CardType.cloze) {
      final existing = base?.clozeIndex ?? 0;
      clozeIndex = specs.any((spec) => spec.clozeIndex == existing)
          ? existing
          : specs.first.clozeIndex;
    }
    if (base != null) {
      return base.copyWith(
        id: id,
        frontText: _frontController.text,
        backText: _backController.text,
        collectionId: _collectionId,
        type: _type,
        tags: List<String>.from(_tags),
        imagePath: _imagePath,
        audioPath: _audioPath,
        reverse: _type == CardType.reversed ? base.reverse : false,
        clozeIndex: clozeIndex,
      );
    }
    return CardItem(
      id: id,
      frontText: _frontController.text,
      backText: _backController.text,
      collectionId: _collectionId,
      type: _type,
      tags: List<String>.from(_tags),
      imagePath: _imagePath,
      audioPath: _audioPath,
      clozeIndex: clozeIndex,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final draft = _draftCard();
    final validation = _validate(draft);
    if (validation != null) {
      setState(() => _error = validation);
      if (_frontController.text.trim().isEmpty) _frontFocus.requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final plan = await HiveService.saveNote(draft);
      if (!mounted) return;
      final primary = plan.cards.firstWhere(
        (card) => card.id == draft.id,
        orElse: () => plan.cards.first,
      );
      _dirty = false;
      Navigator.pop(
        context,
        CardEditorResult(card: primary, cards: plan.cards),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = context.l10n.couldNotSaveCard(error);
        _saving = false;
      });
    }
  }

  String? _validate(CardItem draft) {
    if (_collectionId.trim().isEmpty ||
        HiveService.getCollection(_collectionId) == null) {
      return context.l10n.chooseDeckForCard;
    }
    return draft.validate();
  }

  Future<void> _delete() async {
    final card = widget.card;
    if (card == null) return;
    final l10n = context.l10n;
    final confirmed = await showAppConfirmDialog(
      context,
      title: _isEditing ? l10n.deleteNoteTitle : l10n.deleteCard,
      message: _isEditing ? l10n.deleteNoteBody : l10n.readOnlyNoteBody,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!confirmed) return;
    final deleted = await HiveService.deleteNote(card);
    if (!mounted) return;
    _dirty = false;
    Navigator.pop(
      context,
      CardEditorResult(
        card: deleted.isNotEmpty ? deleted.first : card,
        cards: deleted,
        deleted: true,
      ),
    );
  }

  void _applyMarkup(TextEditingController controller, String marker) {
    final selection = controller.selection;
    final text = controller.text;
    if (selection.isValid && !selection.isCollapsed) {
      final selected = text.substring(selection.start, selection.end);
      final replacement = '$marker$selected$marker';
      controller.value = TextEditingValue(
        text: text.replaceRange(selection.start, selection.end, replacement),
        selection: TextSelection(
          baseOffset: selection.start + marker.length,
          extentOffset: selection.end + marker.length,
        ),
      );
    } else {
      final position = selection.isValid ? selection.start : text.length;
      controller.value = TextEditingValue(
        text: text.replaceRange(position, position, '$marker$marker'),
        selection: TextSelection.collapsed(offset: position + marker.length),
      );
    }
    _markDirty();
  }

  void _insertCloze(TextEditingController controller) {
    final selection = controller.selection;
    final text = controller.text;
    final position = selection.isValid
        ? selection.start
        : _frontController.text.length;
    final end = selection.isValid ? selection.end : position;
    final selected = text.substring(position, end);
    final content = selected.isEmpty ? '' : selected;
    final replacement = '{{c1::$content}}';
    controller.value = TextEditingValue(
      text: text.replaceRange(position, end, replacement),
      selection: TextSelection(
        baseOffset: position + 6,
        extentOffset: position + 6 + content.length,
      ),
    );
    setState(() => _type = CardType.cloze);
  }

  void _addTag() {
    final tag = _tagController.text.trim().replaceAll(RegExp(r'\s+'), '-');
    if (tag.isEmpty) return;
    if (_tags.any((existing) => existing.toLowerCase() == tag.toLowerCase())) {
      _tagController.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _dirty = true;
      _tagController.clear();
    });
  }

  Future<void> _attachImage() async {
    final result = await MediaService.pickImage();
    if (!mounted) return;
    if (result.isSuccess) {
      setState(() {
        _imagePath = result.path;
        _dirty = true;
      });
    } else if (result.error != null) {
      setState(() => _error = result.error);
    }
  }

  Future<void> _attachAudio() async {
    final result = await MediaService.pickAudio();
    if (!mounted) return;
    if (result.isSuccess) {
      setState(() {
        _audioPath = result.path;
        _dirty = true;
      });
    } else if (result.error != null) {
      setState(() => _error = result.error);
    }
  }

  Future<void> _attachByPath({required bool image}) async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          image ? l10n.attachImageFromPath : l10n.attachAudioFromPath,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.filePath,
            hintText: image
                ? '/home/user/Pictures/cell.png'
                : '/home/user/Music/word.mp3',
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
                onPressed: () => Navigator.pop(context, controller.text),
                child: Text(l10n.attach),
              ),
            ],
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || path == null || path.trim().isEmpty) return;
    final result = await MediaService.importPath(path);
    if (!mounted) return;
    if (result.isSuccess) {
      setState(() {
        if (image) {
          _imagePath = result.path;
        } else {
          _audioPath = result.path;
        }
        _dirty = true;
      });
    } else {
      setState(() => _error = result.error);
    }
  }

  Future<void> _confirmDiscard() async {
    final l10n = context.l10n;
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardChanges),
        content: Text(l10n.discardCollectionBody),
        actions: [
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.keepEditing),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.discard),
              ),
            ],
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final decks = _decks;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? l10n.editCardTitle : l10n.newCardTitle),
          actions: [
            if (_isEditing)
              PopupMenuButton<String>(
                tooltip: l10n.cardOptions,
                icon: const Icon(AppIcons.more),
                onSelected: (value) {
                  if (value == 'delete') _delete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(AppIcons.delete),
                      title: Text(l10n.deleteCard),
                    ),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.save),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            final form = _buildForm(context, decks);
            final preview = _buildPreview(context, decks);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: form,
                    ),
                  ),
                  VerticalDivider(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: preview,
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                form,
                const SizedBox(height: 24),
                preview,
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(_isEditing ? l10n.saveChanges : l10n.createCard),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, List<Collection> decks) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.cardType,
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
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
            selected: {_type},
            onSelectionChanged: (value) {
              setState(() {
                _type = value.first;
                _dirty = true;
              });
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.cardTypeDescriptionOf(_type),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_type != CardType.basic) ...[
          const SizedBox(height: 10),
          InfoBanner(
            icon: AppIcons.cloze,
            message: (() {
              final count = const NoteService()
                  .specsFor(_type, _frontController.text)
                  .length;
              return l10n.noteWillCreateCount(count);
            })(),
          ),
        ],
        const SizedBox(height: 18),
        AppSelectField<String>(
          label: l10n.deck,
          valueLabel: _deckLabel(decks),
          value: _collectionId,
          leadingIcon: AppIcons.folder,
          sheetTitle: l10n.deck,
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
            setState(() {
              _collectionId = value;
              _dirty = true;
            });
          },
        ),
        const SizedBox(height: 18),
        _FieldLabel(
          label: _type == CardType.cloze ? l10n.clozeText : l10n.frontLabel,
          hint: _type == CardType.cloze
              ? 'The mitochondria is the {{c1::powerhouse}} of the cell.'
              : l10n.frontHint,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _frontController,
          focusNode: _frontFocus,
          minLines: 3,
          maxLines: 10,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: l10n.questionOrTerm,
            alignLabelWithHint: true,
          ),
        ),
        _FormattingBar(
          onFormat: (marker) => _applyMarkup(_frontController, marker),
          onCloze: _type == CardType.cloze
              ? () => _insertCloze(_frontController)
              : null,
        ),
        const SizedBox(height: 14),
        _FieldLabel(
          label: _type == CardType.cloze
              ? l10n.extraExplanation
              : l10n.backLabel,
          hint: _type == CardType.cloze ? l10n.optionalNotes : l10n.answerHint,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _backController,
          minLines: 3,
          maxLines: 12,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: _type == CardType.cloze
                ? l10n.optionalNotes
                : l10n.answerEllipsis,
            alignLabelWithHint: true,
          ),
        ),
        _FormattingBar(
          onFormat: (marker) => _applyMarkup(_backController, marker),
        ),
        if (_type == CardType.cloze) ...[
          const SizedBox(height: 10),
          InfoBanner(icon: AppIcons.cloze, message: l10n.clozeHint),
        ],
        const SizedBox(height: 22),
        _FieldLabel(label: l10n.tags, hint: l10n.pressEnterToAddTag),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _tagController,
                focusNode: _tagFocus,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addTag(),
                decoration: InputDecoration(hintText: l10n.tagHint),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: _addTag,
                child: const Icon(AppIcons.add),
              ),
            ),
          ],
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in _tags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () {
                    setState(() {
                      _tags.remove(tag);
                      _dirty = true;
                    });
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        _FieldLabel(label: l10n.attachments, hint: l10n.attachmentsHint),
        const SizedBox(height: 8),
        if (_imagePath != null)
          _AttachmentRow(
            icon: AppIcons.image,
            label: MediaService.displayName(_imagePath),
            preview: CardImage(path: _imagePath!, maxHeight: 70),
            onRemove: () => setState(() {
              _imagePath = null;
              _dirty = true;
            }),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _attachImage,
                icon: const Icon(AppIcons.image, size: 18),
                label: Text(l10n.addImage),
              ),
              TextButton(
                onPressed: () => _attachByPath(image: true),
                child: Text(l10n.fromPath),
              ),
            ],
          ),
        const SizedBox(height: 8),
        if (_audioPath != null)
          _AttachmentRow(
            icon: AppIcons.audio,
            label: MediaService.displayName(_audioPath),
            preview: AudioAttachmentButton(path: _audioPath!, compact: true),
            onRemove: () => setState(() {
              _audioPath = null;
              _dirty = true;
            }),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _attachAudio,
                icon: const Icon(AppIcons.audio, size: 18),
                label: Text(l10n.addAudio),
              ),
              TextButton(
                onPressed: () => _attachByPath(image: false),
                child: Text(l10n.fromPath),
              ),
            ],
          ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          InfoBanner(
            icon: AppIcons.error,
            message: _error!,
            color: theme.colorScheme.error,
          ),
        ],
        if (_isEditing) ...[
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: _delete,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(AppIcons.delete),
            label: Text(l10n.deleteCard),
          ),
        ],
      ],
    );
  }

  String _deckLabel(List<Collection> decks) {
    if (!decks.any((deck) => deck.id == _collectionId)) return '';
    final deck = decks.firstWhere((deck) => deck.id == _collectionId);
    return deckLabelWithEmoji(decks, deck);
  }

  Widget _buildPreview(BuildContext context, List<Collection> decks) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final draft = _draftCard(id: widget.card?.id);
    final deck = decks.cast<Collection?>().firstWhere(
      (item) => item?.id == _collectionId,
      orElse: () => null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.livePreview,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(l10n.frontLabel)),
                ButtonSegment(value: true, label: Text(l10n.backLabel)),
              ],
              selected: {_previewBack},
              onSelectionChanged: (value) {
                setState(() => _previewBack = value.first);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (deck?.color ?? theme.colorScheme.outlineVariant)
                  .withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (deck != null) ...[
                Row(
                  children: [
                    AppEmoji(deck.emoji, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        deck.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: deck.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    StatePill(
                      label: l10n.cardTypeLabelOf(_type),
                      color: deck.color,
                    ),
                  ],
                ),
                const Divider(height: 24),
              ],
              if ((_previewBack ? draft.studyBack : draft.studyFront)
                  .trim()
                  .isEmpty)
                Text(
                  l10n.cardPreviewEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                CardContent(card: draft, showAnswer: _previewBack),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.formattingHint,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final String hint;

  const _FieldLabel({required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _FormattingBar extends StatelessWidget {
  final void Function(String marker) onFormat;
  final VoidCallback? onCloze;

  const _FormattingBar({required this.onFormat, this.onCloze});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 2,
        children: [
          _formatButton(context, l10n.bold, AppIcons.bold, '**'),
          _formatButton(context, l10n.italic, AppIcons.italic, '*'),
          _formatButton(context, l10n.underline, AppIcons.underline, '__'),
          _formatButton(context, l10n.highlight, AppIcons.highlight, '=='),
          _formatButton(context, l10n.code, AppIcons.code, '`'),
          if (onCloze != null)
            TextButton.icon(
              onPressed: onCloze,
              icon: const Icon(AppIcons.cloze, size: 17),
              label: Text(l10n.cloze),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _formatButton(
    BuildContext context,
    String tooltip,
    IconData icon,
    String marker,
  ) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 19,
      onPressed: () => onFormat(marker),
      icon: Icon(icon),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget preview;
  final VoidCallback onRemove;

  const _AttachmentRow({
    required this.icon,
    required this.label,
    required this.preview,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: preview),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          IconButton(
            tooltip: context.l10n.removeAttachment,
            onPressed: onRemove,
            icon: const Icon(AppIcons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
