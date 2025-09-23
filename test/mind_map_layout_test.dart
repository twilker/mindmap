import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindmap_app/src/layout/mind_map_layout.dart';
import 'package:mindmap_app/src/models/mind_map_node.dart';
import 'package:mindmap_app/src/utils/constants.dart';

List<String> _linesFromPainter(TextPainter painter) {
  final plainText = painter.text?.toPlainText() ?? '';
  final metrics = painter.computeLineMetrics();
  if (metrics.isEmpty) {
    return [plainText];
  }
  final lines = <String>[];
  var nextStart = 0;
  for (final line in metrics) {
    final lineTop = line.baseline - line.ascent;
    final lineBottom = line.baseline + line.descent;
    final centerY =
        lineTop.isFinite && lineBottom.isFinite ? (lineTop + lineBottom) / 2 : 0.0;
    var centerX = painter.width / 2;
    if (line.left.isFinite && line.width.isFinite) {
      centerX = line.left + line.width / 2;
    }
    final position = painter.getPositionForOffset(Offset(centerX, centerY));
    final range = painter.getLineBoundary(position);
    var start = range.start;
    var end = range.end;
    if (start < nextStart) {
      start = nextStart;
    }
    if (end < start) {
      end = start;
    }
    start = start.clamp(0, plainText.length);
    end = end.clamp(0, plainText.length);
    final text = start < end ? plainText.substring(start, end) : '';
    lines.add(text.replaceAll('\r', '').replaceAll('\n', '').trimRight());
    nextStart = math.max(nextStart, end);
    if (nextStart < plainText.length && plainText.codeUnitAt(nextStart) == 0x0A) {
      nextStart += 1;
    }
  }
  if (lines.isEmpty) {
    return [plainText];
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
