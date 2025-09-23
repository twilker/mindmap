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
  });
}
