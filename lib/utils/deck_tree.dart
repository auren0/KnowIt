import 'package:knowit/models/collection.dart';

/// Optional emoji prefix for deck labels. Empty emoji is a valid choice, so it
/// must not leave a stray leading space or placeholder.
String deckEmojiPrefix(Collection deck) {
  final emoji = deck.emoji.trim();
  return emoji.isEmpty ? '' : '$emoji ';
}

String deckLabelWithEmoji(List<Collection> collections, Collection deck) =>
    '${deckEmojiPrefix(deck)}${deckBreadcrumb(collections, deck)}';

/// A deck plus its children, used to render nested deck lists.
class DeckTreeNode {
  final Collection deck;
  final int depth;
  final List<DeckTreeNode> children;

  DeckTreeNode({
    required this.deck,
    required this.depth,
    List<DeckTreeNode>? children,
  }) : children = children ?? [];

  bool get hasChildren => children.isNotEmpty;
}

/// Builds a forest of decks from a flat list. Orphaned decks (parents that no
/// longer exist) become roots so they can never disappear from the UI.
List<DeckTreeNode> buildDeckForest(List<Collection> collections) {
  final byId = {for (final deck in collections) deck.id: deck};
  final childrenByParent = <String, List<Collection>>{};
  final roots = <Collection>[];

  for (final deck in collections) {
    final parentId = deck.parentId;
    if (parentId != null &&
        parentId.isNotEmpty &&
        byId.containsKey(parentId) &&
        parentId != deck.id) {
      childrenByParent.putIfAbsent(parentId, () => []).add(deck);
    } else {
      roots.add(deck);
    }
  }

  void sortDecks(List<Collection> decks) {
    decks.sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) return order;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  DeckTreeNode buildNode(Collection deck, int depth, Set<String> visiting) {
    if (!visiting.add(deck.id)) {
      return DeckTreeNode(deck: deck, depth: depth);
    }
    final children = (childrenByParent[deck.id] ?? <Collection>[])
        .where((child) => !visiting.contains(child.id))
        .toList();
    sortDecks(children);
    final node = DeckTreeNode(
      deck: deck,
      depth: depth,
      children: [
        for (final child in children) buildNode(child, depth + 1, visiting),
      ],
    );
    visiting.remove(deck.id);
    return node;
  }

  sortDecks(roots);
  return [for (final root in roots) buildNode(root, 0, <String>{})];
}

/// Flattens a forest into rendering order (depth-first).
List<DeckTreeNode> flattenDeckForest(List<DeckTreeNode> forest) {
  final result = <DeckTreeNode>[];
  void visit(DeckTreeNode node) {
    result.add(node);
    for (final child in node.children) {
      visit(child);
    }
  }

  for (final node in forest) {
    visit(node);
  }
  return result;
}

/// All descendant deck ids of [deckId], excluding the deck itself.
Set<String> descendantDeckIds(List<Collection> collections, String deckId) {
  final result = <String>{};
  final pending = <String>[deckId];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    for (final deck in collections) {
      if (deck.parentId == current && result.add(deck.id)) {
        pending.add(deck.id);
      }
    }
  }
  return result;
}

/// Full path like `Biology › Chapter 1`.
String deckBreadcrumb(List<Collection> collections, Collection deck) {
  final byId = {for (final item in collections) item.id: item};
  final parts = <String>[deck.name];
  var parentId = deck.parentId;
  var guard = 0;
  while (parentId != null && parentId.isNotEmpty && guard < 32) {
    final parent = byId[parentId];
    if (parent == null) break;
    parts.insert(0, parent.name);
    parentId = parent.parentId;
    guard++;
  }
  return parts.join(' › ');
}

/// Prevents cycles when changing a deck's parent.
bool wouldCreateCycle(
  List<Collection> collections,
  String deckId,
  String? newParentId,
) {
  if (newParentId == null || newParentId.isEmpty) return false;
  if (newParentId == deckId) return true;
  return descendantDeckIds(collections, deckId).contains(newParentId);
}
