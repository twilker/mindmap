import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/mind_map_node.dart';
import '../utils/json_converter.dart';
import '../utils/markdown_converter.dart';

const _defaultRootText = 'Central Topic';
const _defaultNodeText = 'New Idea';

final mindMapProvider = StateNotifierProvider<MindMapNotifier, MindMapState>((
  ref,
) {
  return MindMapNotifier();
});

class MindMapState {
  MindMapState({
    required this.root,
    required this.document,
    required this.selectedNodeId,
    required this.autoFitVersion,
    this.lastContentBounds,
  });

  final MindMapNode root;
  final String document;
  final String? selectedNodeId;
  final int autoFitVersion;
  final Rect? lastContentBounds;

  MindMapState copyWith({
    MindMapNode? root,
    String? document,
    String? selectedNodeId,
    int? autoFitVersion,
    Rect? lastContentBounds,
    bool updateBounds = false,
  }) {
    return MindMapState(
      root: root ?? this.root,
      document: document ?? this.document,
      selectedNodeId: selectedNodeId ?? this.selectedNodeId,
      autoFitVersion: autoFitVersion ?? this.autoFitVersion,
      lastContentBounds: updateBounds
          ? lastContentBounds
          : this.lastContentBounds,
    );
  }
}

class MindMapNotifier extends StateNotifier<MindMapState> {
  MindMapNotifier() : _uuid = const Uuid(), super(_initialState()) {
    _markdownConverter = MindMapMarkdownConverter(_nextId);
    _jsonConverter = const MindMapJsonConverter();
    final document = _jsonConverter.toJson(state.root);
    state = state.copyWith(document: document, selectedNodeId: state.root.id);
  }

  final Uuid _uuid;
  late MindMapMarkdownConverter _markdownConverter;
  late MindMapJsonConverter _jsonConverter;

  static MindMapState _initialState() {
    final uuid = const Uuid();
    final root = MindMapNode(
      id: uuid.v4(),
      text: _defaultRootText,
      details: '',
      children: const [],
    );
    return MindMapState(
      root: root,
      document: '',
      selectedNodeId: root.id,
      autoFitVersion: 1,
    );
  }

  String _nextId() => _uuid.v4();

  MindMapNode _createNode(String text) => MindMapNode(
        id: _nextId(),
        text: text,
        details: '',
        children: const [],
      );

  void selectNode(String id) {
    if (_findNode(state.root, id) == null) {
      return;
    }
    state = state.copyWith(selectedNodeId: id);
  }

  void updateNodeText(String id, String text) {
    final result = _replaceNode(
      state.root,
      id,
      (node) => node.copyWith(text: text),
    );
    if (!result.modified) {
      return;
    }
    _updateState(result.node, selectedId: id);
  }

  void updateNodeDetails(String id, String details) {
    final normalized = details.replaceAll('\r\n', '\n');
    final result = _replaceNode(
      state.root,
      id,
      (node) => node.copyWith(details: normalized),
    );
    if (!result.modified) {
      return;
    }
    _updateState(result.node, selectedId: id);
  }

  String? addSibling(String nodeId) {
    final newNode = _createNode(_defaultNodeText);
    if (state.root.id == nodeId) {
      final updatedChildren = [...state.root.children, newNode];
      final newRoot = state.root.copyWith(children: updatedChildren);
      _updateState(newRoot, selectedId: newNode.id);
      return newNode.id;
    }
    final result = _insertSibling(state.root, nodeId, newNode);
    if (!result.modified) {
      return null;
    }
    _updateState(result.node, selectedId: newNode.id);
    return newNode.id;
  }

  String? addChild(String parentId) {
    final newNode = _createNode(_defaultNodeText);
    if (state.root.id == parentId) {
      final newRoot = state.root.copyWith(
        children: [...state.root.children, newNode],
      );
      _updateState(newRoot, selectedId: newNode.id);
      return newNode.id;
    }
    final result = _updateChildren(
      state.root,
      parentId,
      (children) => [...children, newNode],
    );
    if (!result.modified) {
      return null;
    }
    _updateState(result.node, selectedId: newNode.id);
    return newNode.id;
  }

  void removeNode(String nodeId) {
    if (state.root.id == nodeId) {
      return;
    }
    final parent = _findParent(state.root, nodeId);
    if (parent == null) {
      return;
    }
    final result = _updateChildren(
      state.root,
      parent.id,
      (children) => [
        for (final child in children)
          if (child.id != nodeId) child,
      ],
    );
    if (!result.modified) {
      return;
    }
    _updateState(result.node, selectedId: parent.id, autoFit: true);
  }

  void importFromMarkdown(String text) {
    final parsed = _markdownConverter.fromMarkdown(text);
    if (parsed == null) {
      return;
    }
    _markdownConverter = MindMapMarkdownConverter(_nextId);
    _updateState(
      parsed,
      selectedId: parsed.id,
      autoFit: true,
      resetBounds: true,
    );
  }

  void importFromJson(String json) {
    final parsed = _jsonConverter.fromJson(json);
    if (parsed == null) {
      return;
    }
    _markdownConverter = MindMapMarkdownConverter(_nextId);
    _updateState(
      parsed,
      selectedId: parsed.id,
      autoFit: true,
      resetBounds: true,
    );
  }

  void setRoot(MindMapNode root) {
    _updateState(root, selectedId: root.id, autoFit: true, resetBounds: true);
  }

  String exportMarkdown() => _markdownConverter.toMarkdown(state.root);

  String exportJson() => state.document;

  MindMapNode? nodeById(String id) => _findNode(state.root, id);

  void requestAutoFit() {
    state = state.copyWith(autoFitVersion: state.autoFitVersion + 1);
  }

  void updateContentBounds(Rect bounds) {
    final current = state.lastContentBounds;
    if (current != null && _rectEquals(current, bounds)) {
      return;
    }
    state = state.copyWith(lastContentBounds: bounds, updateBounds: true);
  }

  MindMapNode? _findNode(MindMapNode node, String id) {
    if (node.id == id) {
      return node;
    }
    for (final child in node.children) {
      final found = _findNode(child, id);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  MindMapNode? _findParent(MindMapNode node, String childId) {
    for (final child in node.children) {
      if (child.id == childId) {
        return node;
      }
      final parent = _findParent(child, childId);
      if (parent != null) {
        return parent;
      }
    }
    return null;
  }

  void _updateState(
    MindMapNode root, {
    String? selectedId,
    bool autoFit = false,
    bool resetBounds = false,
  }) {
    final document = _jsonConverter.toJson(root);
    final selection = selectedId ?? state.selectedNodeId;
    final hasSelection =
        selection != null && _findNode(root, selection) != null;
    state = state.copyWith(
      root: root,
      document: document,
      selectedNodeId: hasSelection ? selection : root.id,
      autoFitVersion: autoFit ? state.autoFitVersion + 1 : state.autoFitVersion,
      lastContentBounds: resetBounds ? null : state.lastContentBounds,
      updateBounds: resetBounds,
    );
  }

  _MutateResult _replaceNode(
    MindMapNode current,
    String id,
    MindMapNode Function(MindMapNode node) transform,
  ) {
    if (current.id == id) {
      return _MutateResult(transform(current), true);
    }
    var changed = false;
    final updatedChildren = <MindMapNode>[];
    for (final child in current.children) {
      final result = _replaceNode(child, id, transform);
      updatedChildren.add(result.node);
      if (result.modified) {
        changed = true;
      }
    }
    if (changed) {
      return _MutateResult(current.copyWith(children: updatedChildren), true);
    }
    return _MutateResult(current, false);
  }

  _MutateResult _updateChildren(
    MindMapNode current,
    String parentId,
    List<MindMapNode> Function(List<MindMapNode> children) transform,
  ) {
    if (current.id == parentId) {
      return _MutateResult(
        current.copyWith(children: transform(current.children)),
        true,
      );
    }
    var changed = false;
    final updatedChildren = <MindMapNode>[];
    for (final child in current.children) {
      final result = _updateChildren(child, parentId, transform);
      updatedChildren.add(result.node);
      if (result.modified) {
        changed = true;
      }
    }
    if (changed) {
      return _MutateResult(current.copyWith(children: updatedChildren), true);
    }
    return _MutateResult(current, false);
  }

  _MutateResult _insertSibling(
    MindMapNode current,
    String targetId,
    MindMapNode sibling,
  ) {
    final children = current.children;
    final updatedChildren = <MindMapNode>[];
    var changed = false;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child.id == targetId) {
        updatedChildren.add(child);
        updatedChildren.add(sibling);
        for (var j = i + 1; j < children.length; j++) {
          updatedChildren.add(children[j]);
        }
        changed = true;
        break;
      }
      final result = _insertSibling(child, targetId, sibling);
      updatedChildren.add(result.node);
      if (result.modified) {
        for (var j = i + 1; j < children.length; j++) {
          updatedChildren.add(children[j]);
        }
        changed = true;
        break;
      }
    }
    if (changed) {
      return _MutateResult(current.copyWith(children: updatedChildren), true);
    }
    return _MutateResult(current, false);
  }

  bool _rectEquals(Rect a, Rect b) {
    const epsilon = 0.5;
    return (a.left - b.left).abs() < epsilon &&
        (a.top - b.top).abs() < epsilon &&
        (a.right - b.right).abs() < epsilon &&
        (a.bottom - b.bottom).abs() < epsilon;
  }
}

class _MutateResult {
  _MutateResult(this.node, this.modified);

  final MindMapNode node;
  final bool modified;
}
