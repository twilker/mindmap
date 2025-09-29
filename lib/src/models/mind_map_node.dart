import 'package:collection/collection.dart';

class MindMapNode {
  const MindMapNode({
    required this.id,
    required this.text,
    this.children = const [],
  });

  final String id;
  final String text;
  final List<MindMapNode> children;

  bool get hasChildren => children.isNotEmpty;

  MindMapNode copyWith({
    String? id,
    String? text,
    List<MindMapNode>? children,
  }) {
    return MindMapNode(
      id: id ?? this.id,
      text: text ?? this.text,
      children: children ?? this.children,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MindMapNode &&
        other.id == id &&
        other.text == text &&
        const DeepCollectionEquality().equals(other.children, children);
  }

  @override
  int get hashCode =>
      Object.hash(id, text, const DeepCollectionEquality().hash(children));
}
