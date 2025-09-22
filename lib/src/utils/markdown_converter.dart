import '../models/mind_map_node.dart';

const String _lineBreak = '\n';

class MindMapMarkdownConverter {
  MindMapMarkdownConverter(this._idGenerator);

  final String Function() _idGenerator;

  List<String> toMarkdownLines(MindMapNode node, {int depth = 0}) {
    final indent = ' ' * (depth * 4);
    final line = '$indent- ${node.text.trim()}';
    final lines = <String>[line];
    for (final child in node.children) {
      lines.addAll(toMarkdownLines(child, depth: depth + 1));
    }
    return lines;
  }

  String toMarkdown(MindMapNode node) => toMarkdownLines(node).join(_lineBreak);

  MindMapNode? fromMarkdown(String text) {
    final normalized = text.replaceAll(String.fromCharCode(13), '');
    final segments = normalized.split(_lineBreak);
    _MutableNode? root;
    final stack = <_MutableNode>[];

    for (final rawLine in segments) {
      if (rawLine.isEmpty) {
        continue;
      }
      final trimmedLeft = rawLine.trimLeft();
      if (!trimmedLeft.startsWith('- ')) {
        continue;
      }
      final indent = rawLine.length - trimmedLeft.length;
      final depth = indent ~/ 4;
      final value = trimmedLeft.substring(2).trim();
      final node = _MutableNode(_idGenerator(), value);

      if (depth == 0) {
        root = node;
        stack
          ..clear()
          ..add(node);
      } else {
        while (stack.length > depth) {
          stack.removeLast();
        }
        if (stack.isEmpty) {
          continue;
        }
        final parent = stack.last;
        parent.children.add(node);
        stack.add(node);
      }
    }

    if (root == null) {
      return null;
    }

    MindMapNode convert(_MutableNode node) {
      return MindMapNode(
        id: node.id,
        text: node.text,
        children: node.children.map(convert).toList(),
      );
    }

    return convert(root);
  }
}

class _MutableNode {
  _MutableNode(this.id, this.text);

  final String id;
  final String text;
  final List<_MutableNode> children = [];
}
