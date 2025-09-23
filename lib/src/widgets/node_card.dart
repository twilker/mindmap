import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/mind_map_layout.dart';
import '../state/mind_map_state.dart';
import '../utils/constants.dart';

class MindMapNodeCard extends ConsumerStatefulWidget {
  const MindMapNodeCard({
    required this.data,
    required this.isSelected,
    required this.accentColor,
    super.key,
  });

  final NodeRenderData data;
  final bool isSelected;
  final Color accentColor;

  @override
  ConsumerState<MindMapNodeCard> createState() => _MindMapNodeCardState();
}

class _MindMapNodeCardState extends ConsumerState<MindMapNodeCard> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.data.node.text);
    _focusNode = FocusNode();
    _focusNode.onKeyEvent = _handleKeyEvent;
    if (widget.isSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _focusNode.hasFocus) {
          return;
        }
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
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
    if (widget.isSelected && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    } else if (!widget.isSelected && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final logicalKey = event.logicalKey;
    final isShiftPressed =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );
    final notifier = ref.read(mindMapProvider.notifier);
    final id = widget.data.node.id;
    if (logicalKey == LogicalKeyboardKey.enter && !isShiftPressed) {
      notifier.addSibling(id);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.tab && !isShiftPressed) {
      notifier.addChild(id);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleTap() {
    ref.read(mindMapProvider.notifier).selectNode(widget.data.node.id);
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
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

  @override
  Widget build(BuildContext context) {
    final highlight = widget.isSelected ? widget.accentColor : Colors.black12;
    final shadowColor = Colors.black.withValues(alpha: Colors.black.a * 0.06);
    return GestureDetector(
      onTap: _handleTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlight,
            width: widget.isSelected ? nodeSelectedBorderWidth : nodeBorderWidth,
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
    );
  }
}
