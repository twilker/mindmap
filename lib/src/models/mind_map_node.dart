import 'package:collection/collection.dart';

class MindMapNode {
  const MindMapNode({
    required this.id,
    required this.text,
    this.details = '',
    this.children = const [],
  });

  final String id;
  final String text;
  final String details;
  final List<MindMapNode> children;

  bool get hasChildren => children.isNotEmpty;

  MindMapNode copyWith({
    String? id,
    String? text,
    String? details,
    List<MindMapNode>? children,
  }) {
    return MindMapNode(
      id: id ?? this.id,
      text: text ?? this.text,
      details: details ?? this.details,
      children: children ?? this.children,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MindMapNode &&
        other.id == id &&
        other.text == text &&
        other.details == details &&
        const DeepCollectionEquality().equals(other.children, children);
  }

  @override
  int get hashCode => Object.hash(
        id,
        text,
        details,
        const DeepCollectionEquality().hash(children),
      );
}
