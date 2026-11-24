import 'package:flutter/material.dart';
import 'package:knowit/l10n/app_localizations.dart';
import 'package:knowit/models/collection.dart';
import 'package:knowit/services/hive_service.dart';
import 'package:knowit/services/stats_service.dart';
import 'package:knowit/theme/app_icons.dart';
import 'package:knowit/utils/deck_tree.dart';
import 'package:knowit/utils/id_generator.dart';
import 'package:knowit/widgets/app_dialog.dart';
import 'package:knowit/widgets/app_emoji.dart';
import 'package:knowit/widgets/collection_card.dart';
import 'package:knowit/widgets/selection_field.dart';

/// Create or edit a collection (deck), including nesting and description.
class CreateCollectionScreen extends StatefulWidget {
  final Collection? collection;
  final String? parentId;

  const CreateCollectionScreen({super.key, this.collection, this.parentId});

  @override
  State<CreateCollectionScreen> createState() => _CreateCollectionScreenState();
}

class _CreateCollectionScreenState extends State<CreateCollectionScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _emojiController;
  late final TextEditingController _descriptionController;

  late Color _selectedColor;
  String? _parentId;
  bool _dirty = false;
  bool _saving = false;

  static const List<Color> _palette = [
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.indigo,
  ];

  static const List<String> _emojiSuggestions = [
    '📚',
    '🧠',
    '🧪',
    '🌍',
    '💻',
    '🎨',
    '🎵',
    '🏛️',
  ];

  bool get _isEditing => widget.collection != null;

  @override
  void initState() {
    super.initState();
    final collection = widget.collection;
    _nameController = TextEditingController(text: collection?.name ?? '')
      ..addListener(_markDirty);
    _emojiController = TextEditingController(text: collection?.emoji ?? '')
      ..addListener(_markDirty);
    _descriptionController = TextEditingController(
      text: collection?.description ?? '',
    )..addListener(_markDirty);
    _selectedColor = collection?.color ?? _palette.first;
    _parentId = collection?.parentId ?? widget.parentId;
  }

  void _markDirty() {
    if (_dirty) {
      setState(() {});
    } else {
      setState(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emojiController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Collection _draft() {
    final existing = widget.collection;
    if (existing != null) {
      return existing.copyWith(
        name: _nameController.text.trim(),
        emoji: _effectiveEmoji,
        color: _selectedColor,
        description: _descriptionController.text.trim(),
        parentId: _parentId,
      );
    }
    return Collection.fromColor(
      id: newId(),
      name: _nameController.text.trim(),
      emoji: _effectiveEmoji,
      color: _selectedColor,
      parentId: _parentId,
      description: _descriptionController.text.trim(),
      sortOrder: HiveService.getAllCollections().length,
    );
  }

  String get _effectiveEmoji {
    final value = _emojiController.text.trim();
    if (value.isEmpty) return '';
    // Keep a single visible grapheme where possible.
    return value.characters.take(2).toString();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pleaseEnterCollectionName)));
      return;
    }
    if (name.length > 60) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.nameTooLong)));
      return;
    }
    final collections = HiveService.getAllCollections();
    if (_parentId != null &&
        wouldCreateCycle(collections, widget.collection?.id ?? '', _parentId)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.parentCycle)));
      return;
    }
    if (_parentId != null && !collections.any((deck) => deck.id == _parentId)) {
      setState(() => _parentId = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.parentMissing)));
      return;
    }

    setState(() => _saving = true);
    try {
      final draft = _draft();
      if (_isEditing) {
        await HiveService.updateCollection(draft);
      } else {
        await HiveService.createCollection(draft);
      }
      await HiveService.refreshCardCounts();
      if (!mounted) return;
      _dirty = false;
      Navigator.pop(context, draft);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.couldNotSaveCollection(error))),
      );
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
    final collections = HiveService.getAllCollections();
    final draft = _draft();
    final metrics = const StatsService().deckMetrics(
      _isEditing ? HiveService.getCardsByCollection(draft.id) : const [],
    );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditing ? l10n.editCollectionTitle : l10n.newCollectionTitle,
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final form = _buildForm(context, collections);
            final preview = _buildPreview(context, draft, metrics);
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
                const SizedBox(height: 16),
              ],
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
            ),
            child: Align(
              alignment: Alignment.center,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_isEditing ? AppIcons.save : AppIcons.add),
                    label: Text(
                      _saving
                          ? l10n.save
                          : _isEditing
                          ? l10n.saveChanges
                          : l10n.createCollection,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, List<Collection> collections) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final validParents = collections.where((deck) {
      if (_isEditing && deck.id == widget.collection!.id) return false;
      if (wouldCreateCycle(collections, widget.collection?.id ?? '', deck.id)) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameController,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.collectionName,
            hintText: l10n.collectionNameHint,
            counterText: '',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _selectedColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: AppEmoji(_effectiveEmoji, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _emojiController,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText:
                      '${l10n.collectionEmoji} (${l10n.optional})',
                  hintText: l10n.enterEmoji,
                  counterText: '',
                  prefixIcon: const Icon(AppIcons.emoji, size: 20),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final emoji in _emojiSuggestions)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  _emojiController.text = emoji;
                  _markDirty();
                },
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AppEmoji(emoji, size: 19),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _descriptionController,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.descriptionOptional,
            hintText: l10n.descriptionHint,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          l10n.accentColor.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in _palette)
              Semantics(
                button: true,
                selected: _selectedColor == color,
                label: l10n.accentColor,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = color;
                      _dirty = true;
                    });
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: _selectedColor == color
                          ? Border.all(
                              width: 3,
                              color: theme.colorScheme.onSurface,
                            )
                          : Border.all(
                              width: 1,
                              color: theme.colorScheme.outlineVariant,
                            ),
                    ),
                    child: _selectedColor == color
                        ? Icon(
                            AppIcons.check,
                            size: 18,
                            color:
                                ThemeData.estimateBrightnessForColor(color) ==
                                    Brightness.light
                                ? Colors.black87
                                : Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        AppSelectField<String>(
          label: l10n.parentCollection,
          valueLabel: _parentId == null
              ? l10n.noneTopLevel
              : _parentLabel(collections, _parentId!),
          value: _parentId ?? '',
          leadingIcon: AppIcons.folder,
          searchable: validParents.length > 8,
          sheetTitle: l10n.parentCollection,
          options: [
            AppSelectOption<String>(
              value: '',
              label: l10n.noneTopLevel,
              icon: AppIcons.folder,
            ),
            for (final deck in validParents)
              AppSelectOption<String>(
                value: deck.id,
                label: deckLabelWithEmoji(collections, deck),
                icon: AppIcons.folder,
              ),
          ],
          onChanged: (value) {
            setState(() {
              _parentId = value.isEmpty ? null : value;
              _dirty = true;
            });
          },
        ),
        const SizedBox(height: 10),
        Text(
          l10n.subcollectionsHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  String _parentLabel(List<Collection> collections, String id) {
    final deck = collections.cast<Collection?>().firstWhere(
      (item) => item?.id == id,
      orElse: () => null,
    );
    if (deck == null) return id;
    return deckLabelWithEmoji(collections, deck);
  }

  Widget _buildPreview(
    BuildContext context,
    Collection draft,
    DeckMetrics metrics,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.livePreview,
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        DeckCard(collection: draft, metrics: metrics, showMenu: false),
        const SizedBox(height: 12),
        Text(
          l10n.progressAutomatic,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
