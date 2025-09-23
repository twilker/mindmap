import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindmap_app/src/layout/mind_map_layout.dart';
import 'package:mindmap_app/src/models/mind_map_node.dart';
import 'package:mindmap_app/src/utils/constants.dart';

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

      final horizontalInset = nodeHorizontalPadding + nodeSelectedBorderWidth;
      final verticalInset = nodeVerticalPadding + nodeSelectedBorderWidth;

      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: nodeMaxWidth - horizontalInset * 2);

      final innerWidth = root!.size.width - horizontalInset * 2;
      final innerHeight = root.size.height - verticalInset * 2;

      expect(root.size.width, equals(root.size.width.roundToDouble()));
      expect(root.size.height, equals(root.size.height.roundToDouble()));
      expect(innerWidth, greaterThanOrEqualTo(painter.width.ceilToDouble()));
      expect(innerHeight, greaterThanOrEqualTo(painter.height.ceilToDouble()));
    });

    test('matches TextPainter height when text soft wraps', () {
      const text = 'Gesundheit als Fundament';
      const node = MindMapNode(id: 'root', text: text);

      final engine = MindMapLayoutEngine(textStyle: textStyle);
      final layout = engine.layout(node);
      final root = layout.nodes[node.id];

      expect(root, isNotNull);

      final horizontalInset = nodeHorizontalPadding + nodeSelectedBorderWidth;
      final verticalInset = nodeVerticalPadding + nodeSelectedBorderWidth;

      final painter = TextPainter(
        text: const TextSpan(text: text, style: textStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: null,
      )..layout(maxWidth: nodeMaxWidth - horizontalInset * 2);

      final metrics = painter.computeLineMetrics();
      expect(metrics.length, greaterThan(1));

      final innerHeight = root!.size.height - verticalInset * 2;

      expect(innerHeight, greaterThanOrEqualTo(painter.height.ceilToDouble()));
    });

    test('respects text scaler when measuring content size', () {
      const text = 'Grundprinzipien';
      const node = MindMapNode(id: 'root', text: text);
      const textScaler = TextScaler.linear(1.5);

      final engine = MindMapLayoutEngine(textStyle: textStyle, textScaler: textScaler);
      final layout = engine.layout(node);
      final root = layout.nodes[node.id];

      expect(root, isNotNull);

      final horizontalInset = nodeHorizontalPadding + nodeSelectedBorderWidth;
      final verticalInset = nodeVerticalPadding + nodeSelectedBorderWidth;

      final painter = TextPainter(
        text: const TextSpan(text: text, style: textStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: null,
        textScaler: textScaler,
      )..layout(maxWidth: nodeMaxWidth - horizontalInset * 2);

      final innerWidth = root!.size.width - horizontalInset * 2;
      final innerHeight = root.size.height - verticalInset * 2;

      expect(innerWidth, greaterThanOrEqualTo(painter.width.ceilToDouble()));
      expect(innerHeight, greaterThanOrEqualTo(painter.height.ceilToDouble()));
    });
  });
}
