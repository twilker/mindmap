import '../models/mind_map_node.dart';

const String _lineBreak = '\n';

class MindMapMarkdownConverter {
  MindMapMarkdownConverter(this._idGenerator);

  final String Function() _idGenerator;

  List<String> toMarkdownLines(MindMapNode node, {int depth = 0}) {
    final indent = ' ' * (depth * 4);
    final line = '$indent- ${node.text.trim()}';
    final lines = <String>[line];
    final rawDetails = node.details.replaceAll('\r', '');
    if (rawDetails.trim().isNotEmpty) {
      final detailsIndent = ' ' * ((depth + 1) * 4);
      final paragraphs = rawDetails.split(RegExp(r'\n\s*\n'));
      final continuationIndent = '$detailsIndent   ';
      for (final paragraph in paragraphs) {
        if (paragraph.trim().isEmpty) {
          continue;
        }
        final paragraphLines = paragraph.split('\n');
        final firstLine = paragraphLines.first;
        lines.add('$detailsIndent-> $firstLine');
        for (var i = 1; i < paragraphLines.length; i++) {
          lines.add('$continuationIndent${paragraphLines[i]}');
        }
      }
    }
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

    _PendingDetails? pendingDetails;

    void flushPendingDetails() {
      if (pendingDetails == null) {
        return;
      }
      pendingDetails!.target.details.add(pendingDetails!.buffer.toString());
      pendingDetails = null;
    }

    for (final rawLine in segments) {
      if (rawLine.isEmpty) {
        continue;
      }
      final trimmedLeft = rawLine.trimLeft();
      if (pendingDetails != null) {
        final pending = pendingDetails!;
        final depth = pending.depth;
        final indent = rawLine.length - trimmedLeft.length;
        final isContinuation =
            indent > pending.baseIndent &&
            indent ~/ 4 == depth &&
            !trimmedLeft.startsWith('- ') &&
            !trimmedLeft.startsWith('-> ');
        if (isContinuation) {
          final tentativeStart =
              indent > pending.baseIndent ? pending.baseIndent + 3 : indent;
          final startIndex =
              tentativeStart.clamp(0, rawLine.length).toInt();
          final content = rawLine.substring(startIndex);
          pending.buffer.write('\n');
          pending.buffer.write(content);
          continue;
        } else {
          flushPendingDetails();
        }
      }
      if (trimmedLeft.startsWith('-> ')) {
        final indent = rawLine.length - trimmedLeft.length;
        final depth = indent ~/ 4;
        if (depth == 0 || stack.length < depth) {
          continue;
        }
        final parent = stack[depth - 1];
        final content = trimmedLeft.substring(3);
        pendingDetails = _PendingDetails(
          target: parent,
          depth: depth,
          baseIndent: indent,
          buffer: StringBuffer(content),
        );
        continue;
      }
      if (!trimmedLeft.startsWith('- ')) {
        flushPendingDetails();
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
        flushPendingDetails();
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

    flushPendingDetails();

    if (root == null) {
      return null;
    }

    MindMapNode convert(_MutableNode node) {
      return MindMapNode(
        id: node.id,
        text: node.text,
        details: node.details.isEmpty
            ? ''
            : node.details.join('\n\n'),
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
  final List<String> details = [];
  final List<_MutableNode> children = [];
}

class _PendingDetails {
  _PendingDetails({
    required this.target,
    required this.depth,
    required this.baseIndent,
    required this.buffer,
  });

  final _MutableNode target;
  final int depth;
  final int baseIndent;
  final StringBuffer buffer;
}
