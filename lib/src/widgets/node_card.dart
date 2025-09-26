import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/mind_map_layout.dart';
import '../state/layout_snapshot.dart';
import '../state/mind_map_state.dart';
import '../state/node_edit_request.dart';
import '../utils/constants.dart';

typedef FocusOnNodeCallback = void Function(String id, {bool preferTopHalf});

typedef NodeEditingChangedCallback =
    void Function(String id, bool isEditing, {bool preferTopHalf});

class MindMapNodeCard extends ConsumerStatefulWidget {
  const MindMapNodeCard({
    required this.data,
    required this.isSelected,
    required this.accentColor,
    this.onRequestFocusOnNode,
    this.onEditingChanged,
    super.key,
  });

  final NodeRenderData data;
  final bool isSelected;
  final Color accentColor;
  final FocusOnNodeCallback? onRequestFocusOnNode;
  final NodeEditingChangedCallback? onEditingChanged;

  @override
  ConsumerState<MindMapNodeCard> createState() => _MindMapNodeCardState();
}

class _MindMapNodeCardState extends ConsumerState<MindMapNodeCard> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _updating = false;
  bool _pendingFocusRequest = false;
  late final ProviderSubscription<String?> _editRequestSubscription;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.data.node.text);
    _focusNode = FocusNode();
    _focusNode.onKeyEvent = _handleKeyEvent;
    _focusNode.addListener(_handleFocusChange);
    _editRequestSubscription = ref.listenManual<String?>(
      nodeEditRequestProvider,
      (previous, next) {
        if (next == widget.data.node.id) {
          _handleEditPressed();
          final notifier = ref.read(nodeEditRequestProvider.notifier);
          if (notifier.state == widget.data.node.id) {
            notifier.state = null;
          }
        }
      },
    );
    if (widget.isSelected) {
      _scheduleFocusRequest();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    _editRequestSubscription.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MindMapNodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data.node.text != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.data.node.text,
        selection: TextSelection.collapsed(
          offset: widget.data.node.text.length,
        ),
      );
    }
    if (widget.isSelected) {
      _scheduleFocusRequest();
    } else if (_focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final logicalKey = event.logicalKey;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final isShiftPressed =
        pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
    final isAltPressed =
        pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight) ||
        pressed.contains(LogicalKeyboardKey.alt);
    if (isAltPressed &&
        (logicalKey == LogicalKeyboardKey.arrowLeft ||
            logicalKey == LogicalKeyboardKey.arrowRight ||
            logicalKey == LogicalKeyboardKey.arrowUp ||
            logicalKey == LogicalKeyboardKey.arrowDown)) {
      final targetId = _resolveNavigationTarget(logicalKey);
      if (targetId != null && targetId != widget.data.node.id) {
        ref.read(mindMapProvider.notifier).selectNode(targetId);
        widget.onRequestFocusOnNode?.call(targetId);
      }
      return KeyEventResult.handled;
    }
    final notifier = ref.read(mindMapProvider.notifier);
    final id = widget.data.node.id;
    if (logicalKey == LogicalKeyboardKey.enter && !isShiftPressed) {
      final newId = notifier.addSibling(id);
      if (newId != null) {
        widget.onRequestFocusOnNode?.call(newId);
      }
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.tab && !isShiftPressed) {
      final newId = notifier.addChild(id);
      if (newId != null) {
        widget.onRequestFocusOnNode?.call(newId);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String? _resolveNavigationTarget(LogicalKeyboardKey key) {
    final snapshot = ref.read(mindMapLayoutSnapshotProvider);
    if (snapshot == null) {
      return null;
    }
    final nodes = snapshot.nodes;
    final current = nodes[widget.data.node.id];
    if (current == null) {
      return null;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return _resolveHorizontalTarget(nodes, current, key);
    }
    final moveUp = key == LogicalKeyboardKey.arrowUp;
    return _resolveVerticalTarget(nodes, current, moveUp);
  }

  String? _resolveHorizontalTarget(
    Map<String, NodeRenderData> nodes,
    NodeRenderData current,
    LogicalKeyboardKey key,
  ) {
    if (current.parentId == null) {
      final bool toLeft = key == LogicalKeyboardKey.arrowLeft;
      final children = _collectChildren(
        nodes,
        current.node.id,
        isLeft: toLeft ? true : false,
      );
      if (children.isEmpty) {
        return null;
      }
      return children[children.length ~/ 2].node.id;
    }

    final bool towardsChildren =
        (key == LogicalKeyboardKey.arrowLeft && current.isLeft) ||
        (key == LogicalKeyboardKey.arrowRight && !current.isLeft);
    if (towardsChildren) {
      final children = _collectChildren(nodes, current.node.id);
      if (children.isEmpty) {
        return null;
      }
      return children[children.length ~/ 2].node.id;
    }

    return current.parentId;
  }

  String? _resolveVerticalTarget(
    Map<String, NodeRenderData> nodes,
    NodeRenderData current,
    bool moveUp,
  ) {
    final peers = [
      for (final candidate in nodes.values)
        if (candidate.isLeft == current.isLeft &&
            candidate.depth == current.depth)
          candidate,
    ]..sort((a, b) => a.center.dy.compareTo(b.center.dy));
    final index = peers.indexWhere((node) => node.node.id == current.node.id);
    if (index == -1) {
      return null;
    }
    final nextIndex = moveUp ? index - 1 : index + 1;
    if (nextIndex < 0 || nextIndex >= peers.length) {
      return null;
    }
    return peers[nextIndex].node.id;
  }

  List<NodeRenderData> _collectChildren(
    Map<String, NodeRenderData> nodes,
    String parentId, {
    bool? isLeft,
  }) {
    return [
      for (final candidate in nodes.values)
        if (candidate.parentId == parentId &&
            (isLeft == null || candidate.isLeft == isLeft))
          candidate,
    ]..sort((a, b) => a.center.dy.compareTo(b.center.dy));
  }

  void _handleTap() {
    ref.read(mindMapProvider.notifier).selectNode(widget.data.node.id);
    if (!_isTouchOnlyDevice()) {
      _startEditing();
    }
  }

  void _handleEditPressed() {
    ref.read(mindMapProvider.notifier).selectNode(widget.data.node.id);
    _startEditing();
  }

  void _startEditing() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    widget.onRequestFocusOnNode?.call(
      widget.data.node.id,
      preferTopHalf: _isTouchOnlyDevice(),
    );
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      ref.read(mindMapProvider.notifier).selectNode(widget.data.node.id);
    }
    widget.onEditingChanged?.call(
      widget.data.node.id,
      _focusNode.hasFocus,
      preferTopHalf: _isTouchOnlyDevice(),
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _handleChanged(String value) {
    if (_updating) {
      return;
    }
    _updating = true;
    ref
        .read(mindMapProvider.notifier)
        .updateNodeText(widget.data.node.id, value);
    _updating = false;
  }

  void _scheduleFocusRequest() {
    if (_isTouchOnlyDevice() || _focusNode.hasFocus || _pendingFocusRequest) {
      return;
    }
    _pendingFocusRequest = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _pendingFocusRequest = false;
      if (widget.isSelected && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  bool _isTouchOnlyDevice() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        return true;
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final highlight = widget.isSelected ? widget.accentColor : Colors.black12;
    final shadowColor = Colors.black.withValues(alpha: Colors.black.a * 0.06);
    final isTouchOnly = _isTouchOnlyDevice();
    final ignoreTextInput = isTouchOnly && !_focusNode.hasFocus;
    return GestureDetector(
      onTap: _handleTap,
      onDoubleTap: _handleEditPressed,
      onLongPress: isTouchOnly ? _handleEditPressed : null,
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: highlight,
                width: widget.isSelected
                    ? nodeSelectedBorderWidth
                    : nodeBorderWidth,
              ),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: nodeHorizontalPadding,
                vertical: nodeVerticalPadding,
              ),
              child: IgnorePointer(
                ignoring: ignoreTextInput,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: _handleChanged,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlign: TextAlign.center,
                  style: textStyle,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
