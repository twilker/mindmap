import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindmap_app/src/layout/mind_map_layout.dart';
import 'package:mindmap_app/src/models/mind_map_node.dart';
import 'package:mindmap_app/src/utils/constants.dart';

List<String> _linesFromPainter(TextPainter painter) {
  final plainText = painter.text?.toPlainText() ?? '';
  final length = plainText.length;
  if (length == 0) {
    return [''];
  }

  final ranges = <TextRange>[];
  var offset = 0;
  while (offset < length) {
    final boundary = painter.getLineBoundary(TextPosition(offset: offset));
    var start = math.max(boundary.start, 0);
    var end = math.min(boundary.end, length);
    if (start < offset) {
      start = offset;
    }
    if (end <= start) {
      end = math.min(length, start + 1);
    }
    ranges.add(TextRange(start: start, end: end));
    offset = end;
    if (offset >= length) {
      break;
    }

    var newlineCount = 0;
    while (offset < length) {
      final unit = plainText.codeUnitAt(offset);
      if (unit == 0x0D) {
        offset++;
        if (offset < length && plainText.codeUnitAt(offset) == 0x0A) {
          offset++;
        }
        newlineCount++;
        continue;
      }
      if (unit == 0x0A) {
        offset++;
        newlineCount++;
        continue;
      }
      break;
    }
    if (newlineCount > 0) {
      if (offset >= length) {
        for (var i = 0; i < newlineCount; i++) {
          ranges.add(TextRange(start: length, end: length));
        }
        break;
      }
      for (var i = 1; i < newlineCount; i++) {
        ranges.add(TextRange(start: offset, end: offset));
      }
    }
  }

  if (ranges.isEmpty) {
    ranges.add(TextRange(start: 0, end: length));
  }

  var trailingNewlines = 0;
  var index = length - 1;
  while (index >= 0) {
    final unit = plainText.codeUnitAt(index);
    if (unit == 0x0A) {
      trailingNewlines++;
      index--;
      if (index >= 0 && plainText.codeUnitAt(index) == 0x0D) {
        index--;
      }
      continue;
    }
    if (unit == 0x0D) {
      trailingNewlines++;
      index--;
      continue;
    }
    break;
  }

  var existingTrailing = 0;
  for (var i = ranges.length - 1; i >= 0; i--) {
    final range = ranges[i];
    if (range.start == length && range.end == length) {
      existingTrailing++;
    } else {
      break;
    }
  }
  for (var i = existingTrailing; i < trailingNewlines; i++) {
    ranges.add(TextRange(start: length, end: length));
  }

  final lines = <String>[];
  for (final range in ranges) {
    final start = math.max(0, math.min(range.start, length));
    final end = math.max(start, math.min(range.end, length));
    final fragment = start < end ? plainText.substring(start, end) : '';
    lines.add(fragment.replaceAll('\r', '').replaceAll('\n', '').trimRight());
  }
  return lines;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MindMapLayoutEngine text measurement', () {
    test('wraps long text without hanging', () {
      const longText =
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.';
      const node = MindMapNode(id: 'root', text: longText);

      final engine = MindMapLayoutEngine(textStyle: textStyle);
      final layout = engine.layout(node);
      final root = layout.nodes[node.id];

      expect(root, isNotNull);
      expect(root!.lines.length, greaterThan(1));
    });

    test('respects explicit newline characters', () {
      const text = 'First line\nSecond line';
      const node = MindMapNode(id: 'root', text: text);

      final engine = MindMapLayoutEngine(textStyle: textStyle);
      final layout = engine.layout(node);
      final root = layout.nodes[node.id];

      expect(root, isNotNull);
      expect(root!.lines, containsAllInOrder(['First line', 'Second line']));
    });

    test('keeps empty lines when text contains consecutive newlines', () {
      const text = 'Line one\n\nLine three';
      const node = MindMapNode(id: 'root', text: text);

      final engine = MindMapLayoutEngine(textStyle: textStyle);
      final layout = engine.layout(node);
      final root = layout.nodes[node.id];

      expect(root, isNotNull);
      expect(root!.lines.length, 3);
      expect(root.lines[1].trim(), isEmpty);
    });

    test('rounds measured size up to avoid clipping fractional metrics', () {
      const text = 'ABCDE FGHIJ';
      final style = textStyle.copyWith(fontSize: 15.3);
      const node = MindMapNode(id: 'root', text: text);

      final engine = MindMapLayoutEngine(textStyle: style);
      final layout = engine.layout(node);
      final root = layout.nodes[node.id];

      expect(root, isNotNull);

      const horizontalPadding = nodeHorizontalPadding;
      const verticalPadding = nodeVerticalPadding;

      const caretMargin = nodeCaretMargin;
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: nodeMaxWidth - horizontalPadding * 2 - caretMargin);

      final innerWidth = root!.size.width - horizontalPadding * 2;
      final innerHeight = root.size.height - verticalPadding * 2;

      expect(root.size.width, equals(root.size.width.roundToDouble()));
      expect(root.size.height, equals(root.size.height.roundToDouble()));
      expect(innerWidth, greaterThanOrEqualTo(painter.width + caretMargin));
      expect(innerHeight, greaterThanOrEqualTo(painter.height.ceilToDouble()));
    });

    test('matches TextPainter height when text soft wraps', () {
      const text = 'Gesundheit als Fundament';
      const node = MindMapNode(id: 'root', text: text);

      final engine = MindMapLayoutEngine(textStyle: textStyle);
      final layout = engine.layout(node);
      final root = layout.nodes[node.id];

      expect(root, isNotNull);

      const horizontalPadding = nodeHorizontalPadding;
      const verticalPadding = nodeVerticalPadding;

      const caretMargin = nodeCaretMargin;
      final painter = TextPainter(
        text: const TextSpan(text: text, style: textStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: nodeMaxWidth - horizontalPadding * 2 - caretMargin);

      final metrics = painter.computeLineMetrics();
      expect(metrics.length, greaterThan(1));

      final innerHeight = root!.size.height - verticalPadding * 2;
      final expectedLines = _linesFromPainter(painter);

      expect(root.lines, equals(expectedLines));

      expect(innerHeight, greaterThanOrEqualTo(painter.height.ceilToDouble()));
    });

    test('respects text scaler when measuring content size', () {
      const text = 'Grundprinzipien';
      const node = MindMapNode(id: 'root', text: text);
      const textScaler = TextScaler.linear(1.5);

      final engine = MindMapLayoutEngine(
        textStyle: textStyle,
        textScaler: textScaler,
      );
      final layout = engine.layout(node);
      final root = layout.nodes[node.id];

      expect(root, isNotNull);

      const horizontalPadding = nodeHorizontalPadding;
      const verticalPadding = nodeVerticalPadding;

      const caretMargin = nodeCaretMargin;
      final painter = TextPainter(
        text: const TextSpan(text: text, style: textStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: null,
        textScaler: textScaler,
      )..layout(maxWidth: nodeMaxWidth - horizontalPadding * 2 - caretMargin);

      final innerWidth = root!.size.width - horizontalPadding * 2;
      final innerHeight = root.size.height - verticalPadding * 2;

      expect(innerWidth, greaterThanOrEqualTo(painter.width + caretMargin));
      expect(innerHeight, greaterThanOrEqualTo(painter.height.ceilToDouble()));
    });

    test('captures all wrapped lines for long descriptive text', () {
      const text =
          'Äußere Gesundheit: Physische Fitness, ausgewogene Ernährung und ein achtsamer Lebensstil.';
      const node = MindMapNode(id: 'root', text: text);

      final engine = MindMapLayoutEngine(textStyle: textStyle);
      final layout = engine.layout(node);
      final root = layout.nodes[node.id];

      expect(root, isNotNull);

      const horizontalPadding = nodeHorizontalPadding;
      const caretMargin = nodeCaretMargin;
      final painter = TextPainter(
        text: const TextSpan(text: text, style: textStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: nodeMaxWidth - horizontalPadding * 2 - caretMargin);

      final expectedLines = _linesFromPainter(painter);
      expect(root!.lines, equals(expectedLines));
      String normalize(String value) => value.replaceAll(RegExp(r'\s+'), '');
      expect(normalize(root.lines.join('\n')), equals(normalize(text)));
    });
  });
}
