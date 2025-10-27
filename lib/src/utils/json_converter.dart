import 'dart:convert';

import '../models/mind_map_node.dart';

class MindMapJsonConverter {
  const MindMapJsonConverter();

  static const int _currentVersion = 1;

  String toJson(MindMapNode root) {
    final map = <String, dynamic>{
      'version': _currentVersion,
      'root': _nodeToMap(root),
    };
    return jsonEncode(map);
  }

  MindMapNode? fromJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final root = decoded['root'];
      if (root is! Map<String, dynamic>) {
        return null;
      }
      return _nodeFromMap(root);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _nodeToMap(MindMapNode node) {
    return {
      'id': node.id,
      'text': node.text,
      'details': node.details,
      'children': [
        for (final child in node.children) _nodeToMap(child),
      ],
    };
  }

  MindMapNode? _nodeFromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final text = map['text'];
    if (id is! String || text is! String) {
      return null;
    }
    final detailsValue = map['details'];
    final details = detailsValue is String ? detailsValue : '';
    final childrenValue = map['children'];
    final children = <MindMapNode>[];
    if (childrenValue is List) {
      for (final entry in childrenValue) {
        if (entry is Map<String, dynamic>) {
          final child = _nodeFromMap(entry);
          if (child != null) {
            children.add(child);
          }
        }
      }
    }
    return MindMapNode(
      id: id,
      text: text,
      details: details,
      children: children,
    );
  }
}
