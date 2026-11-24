import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

final RegExp _soundPattern = RegExp(r'\[sound:([^\]]+)\]');

/// Converts Anki/AI HTML into KnowIt's lightweight markup while preserving
/// basic formatting. Scripts and styles are discarded, never rendered.
String htmlToMarkup(String raw) {
  if (raw.trim().isEmpty) return '';
  final hasHtml = RegExp(r'<[a-zA-Z!/]').hasMatch(raw);
  if (!hasHtml) return _clean(raw);

  final fragment = html_parser.parseFragment(raw);
  final buffer = StringBuffer();

  void visit(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.text);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName?.toLowerCase();
    switch (tag) {
      case 'script':
      case 'style':
      case 'head':
      case 'audio':
      case 'video':
        return;
      case 'br':
        buffer.write('\n');
        return;
      case 'div':
      case 'p':
      case 'li':
        if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
          buffer.write('\n');
        }
        node.nodes.forEach(visit);
        if (!buffer.toString().endsWith('\n')) buffer.write('\n');
        return;
      case 'b':
      case 'strong':
        buffer.write('**');
        node.nodes.forEach(visit);
        buffer.write('**');
        return;
      case 'i':
      case 'em':
        buffer.write('*');
        node.nodes.forEach(visit);
        buffer.write('*');
        return;
      case 'u':
        buffer.write('__');
        node.nodes.forEach(visit);
        buffer.write('__');
        return;
      case 'code':
        buffer.write('`');
        node.nodes.forEach(visit);
        buffer.write('`');
        return;
      case 'img':
        // Extracted separately as an attachment reference.
        return;
      default:
        node.nodes.forEach(visit);
    }
  }

  fragment.nodes.forEach(visit);
  return _clean(buffer.toString());
}

String _clean(String value) {
  return value
      .replaceAll(_soundPattern, '')
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Collects image/audio references from Anki note HTML.
List<String> extractMediaReferences(String raw) {
  final references = <String>[];
  for (final match in _soundPattern.allMatches(raw)) {
    final name = match.group(1)?.trim();
    if (name != null && name.isNotEmpty) references.add(name);
  }
  if (RegExp(r'<[a-zA-Z!/]').hasMatch(raw)) {
    final fragment = html_parser.parseFragment(raw);
    for (final element in fragment.querySelectorAll('img, audio, source')) {
      final source =
          element.attributes['src'] ?? element.attributes['data-src'] ?? '';
      if (source.trim().isNotEmpty) references.add(source.trim());
    }
  }
  return references.toSet().toList();
}

String normalizeForDuplicate(String value) {
  return htmlToMarkup(value)
      .toLowerCase()
      .replaceAll(RegExp(r'\{\{c\d+::'), ' ')
      .replaceAll(RegExp(r'\}\}'), ' ')
      .replaceAll(RegExp(r"""[ *_`=#>\-?.,!;:"“”'()\[\]{}<>/\\|~…]"""), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Converts KnowIt markup into HTML for Anki note fields.
String markupToAnkiHtml(String text) {
  var value = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  value = value.replaceAllMapped(
    RegExp(r'\*\*(.+?)\*\*', dotAll: true),
    (m) => '<b>${m.group(1)}</b>',
  );
  value = value.replaceAllMapped(
    RegExp(r'__(.+?)__', dotAll: true),
    (m) => '<u>${m.group(1)}</u>',
  );
  value = value.replaceAllMapped(
    RegExp(r'==(.+?)==', dotAll: true),
    (m) => '<span style="background-color:#fff3a0">${m.group(1)}</span>',
  );
  value = value.replaceAllMapped(
    RegExp(r'`(.+?)`', dotAll: true),
    (m) => '<code>${m.group(1)}</code>',
  );
  value = value.replaceAllMapped(
    RegExp(r'\*([^*\n]+)\*'),
    (m) => '<i>${m.group(1)}</i>',
  );
  return value.replaceAll('\n', '<br>');
}
