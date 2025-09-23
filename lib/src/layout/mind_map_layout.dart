import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';

import '../models/mind_map_node.dart';
import '../utils/constants.dart';

class MindMapLayoutResult {
  MindMapLayoutResult({required this.nodes, required this.bounds});

  final Map<String, NodeRenderData> nodes;
  final Rect bounds;

  bool get isEmpty => nodes.isEmpty;
}

class NodeRenderData {
  NodeRenderData({
    required this.node,
    required this.center,
    required this.size,
    required this.lines,
    required this.branchIndex,
    required this.isLeft,
    required this.parentId,
  });

  final MindMapNode node;
  final Offset center;
  final Size size;
  final List<String> lines;
  final int branchIndex;
  final bool isLeft;
  final String? parentId;

  Offset get topLeft =>
      Offset(center.dx - size.width / 2, center.dy - size.height / 2);

  Rect get rect =>
      Rect.fromCenter(center: center, width: size.width, height: size.height);
}

class MindMapLayoutEngine {
  MindMapLayoutEngine({required this.textStyle, TextScaler? textScaler})
    : textScaler = textScaler ?? TextScaler.noScaling;

  final TextStyle textStyle;
  final TextScaler textScaler;

  MindMapLayoutResult layout(MindMapNode root) {
    final measuredRoot = _measure(root);
    final nodes = <String, NodeRenderData>{};
    Rect? bounds;

    void addNode(NodeRenderData data) {
      nodes[data.node.id] = data;
      bounds = bounds == null ? data.rect : bounds!.expandToInclude(data.rect);
    }

    final rootData = NodeRenderData(
      node: measuredRoot.node,
      center: Offset.zero,
      size: measuredRoot.size,
      lines: measuredRoot.lines,
      branchIndex: -1,
      isLeft: false,
      parentId: null,
    );
    addNode(rootData);

    if (measuredRoot.children.isEmpty) {
      return MindMapLayoutResult(nodes: nodes, bounds: bounds ?? Rect.zero);
    }

    final branches = <_Branch>[];
    for (var index = 0; index < measuredRoot.children.length; index++) {
      branches.add(_Branch(measuredRoot.children[index], index));
    }
    final sorted = [...branches]
      ..sort((a, b) => b.node.totalHeight.compareTo(a.node.totalHeight));

    final left = <_Branch>[];
    final right = <_Branch>[];
    var leftHeight = 0.0;
    var rightHeight = 0.0;
    for (final branch in sorted) {
      if (leftHeight <= rightHeight) {
        left.add(branch);
        leftHeight += branch.node.totalHeight;
      } else {
        right.add(branch);
        rightHeight += branch.node.totalHeight;
      }
    }

    left.sort((a, b) => a.index.compareTo(b.index));
    right.sort((a, b) => a.index.compareTo(b.index));

    final leftBlockHeight = _stackHeight(left.map((b) => b.node).toList());
    var currentLeftY = rootData.center.dy - leftBlockHeight / 2;
    for (var i = 0; i < left.length; i++) {
      final branch = left[i];
      final childCenterY = currentLeftY + branch.node.totalHeight / 2;
      final childCenterX =
          rootData.center.dx -
          (rootData.size.width / 2 +
              nodeHorizontalGap +
              branch.node.size.width / 2);
      _layoutSubtree(
        branch.node,
        Offset(childCenterX, childCenterY),
        true,
        branch.index,
        rootData.node.id,
        addNode,
      );
      currentLeftY += branch.node.totalHeight;
      if (i < left.length - 1) {
        currentLeftY += nodeVerticalGap;
      }
    }

    final rightBlockHeight = _stackHeight(right.map((b) => b.node).toList());
    var currentRightY = rootData.center.dy - rightBlockHeight / 2;
    for (var i = 0; i < right.length; i++) {
      final branch = right[i];
      final childCenterY = currentRightY + branch.node.totalHeight / 2;
      final childCenterX =
          rootData.center.dx +
          (rootData.size.width / 2 +
              nodeHorizontalGap +
              branch.node.size.width / 2);
      _layoutSubtree(
        branch.node,
        Offset(childCenterX, childCenterY),
        false,
        branch.index,
        rootData.node.id,
        addNode,
      );
      currentRightY += branch.node.totalHeight;
      if (i < right.length - 1) {
        currentRightY += nodeVerticalGap;
      }
    }

    return MindMapLayoutResult(nodes: nodes, bounds: bounds ?? Rect.zero);
  }

  _MeasuredNode _measure(MindMapNode node) {
    final displayText = node.text.isEmpty ? ' ' : node.text;
    final horizontalPadding = nodeHorizontalPadding;
    final verticalPadding = nodeVerticalPadding;
    final maxTextWidth = math.max(
      0.0,
      nodeMaxWidth - horizontalPadding * 2,
    ); // guard for tiny max widths

    final painter = TextPainter(
      text: TextSpan(text: displayText, style: textStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: null,
      textScaler: textScaler,
    )..layout(maxWidth: maxTextWidth);

    final plainText = painter.text?.toPlainText() ?? displayText;
    final metrics = painter.computeLineMetrics();
    final lines = <String>[];
    if (metrics.isEmpty) {
      lines.add(plainText);
    } else {
      for (final line in metrics) {
        final lineTop = line.baseline - line.ascent;
        final dy = lineTop.isFinite ? lineTop + 0.1 : 0.0;
        final dx = line.left.isFinite ? line.left + 0.1 : 0.0;
        final position = painter.getPositionForOffset(Offset(dx, dy));
        final range = painter.getLineBoundary(position);
        final start = range.start.clamp(0, plainText.length);
        final end = range.end.clamp(0, plainText.length);
        if (end > start) {
          final substring = plainText.substring(start, end);
          lines.add(substring.replaceAll('\n', '').trimRight());
        } else {
          lines.add('');
        }
      }
    }
    if (lines.isEmpty) {
      lines.add(node.text);
    }

    var contentWidth = painter.width;
    var contentHeight = painter.height;
    if (metrics.isNotEmpty) {
      var minLeft = double.infinity;
      var maxRight = double.negativeInfinity;
      var minTop = double.infinity;
      var maxBottom = double.negativeInfinity;
      for (final line in metrics) {
        if (line.left.isFinite) {
          minLeft = math.min(minLeft, line.left);
          final right = line.left + line.width;
          if (right.isFinite) {
            maxRight = math.max(maxRight, right);
          }
        }
        final lineTop = line.baseline - line.ascent;
        final lineBottom = line.baseline + line.descent;
        if (lineTop.isFinite) {
          minTop = math.min(minTop, lineTop);
        }
        if (lineBottom.isFinite) {
          maxBottom = math.max(maxBottom, lineBottom);
        }
      }
      if (minLeft.isFinite && maxRight.isFinite) {
        contentWidth = math.max(contentWidth, maxRight - minLeft);
      }
      if (minTop.isFinite && maxBottom.isFinite) {
        contentHeight = math.max(contentHeight, maxBottom - minTop);
      }
    }

    final width = math.max(
      nodeMinWidth,
      math.min(
        nodeMaxWidth,
        (contentWidth + horizontalPadding * 2).ceilToDouble(),
      ),
    );
    final height = math.max(
      nodeMinHeight,
      (contentHeight + verticalPadding * 2).ceilToDouble(),
    );

    final children = node.children.map(_measure).toList();
    final childrenHeight = _stackHeight(children);
    final totalHeight = children.isEmpty
        ? height
        : childrenHeight > height
        ? childrenHeight
        : height;

    return _MeasuredNode(
      node: node,
      size: Size(width, height),
      totalHeight: totalHeight,
      childrenHeight: childrenHeight,
      lines: lines,
      children: children,
    );
  }

  void _layoutSubtree(
    _MeasuredNode measured,
    Offset center,
    bool isLeft,
    int branchIndex,
    String parentId,
    void Function(NodeRenderData data) addNode,
  ) {
    final data = NodeRenderData(
      node: measured.node,
      center: center,
      size: measured.size,
      lines: measured.lines,
      branchIndex: branchIndex,
      isLeft: isLeft,
      parentId: parentId,
    );
    addNode(data);

    if (measured.children.isEmpty) {
      return;
    }

    final blockHeight = measured.childrenHeight > 0
        ? measured.childrenHeight
        : measured.size.height;
    var currentY = center.dy - blockHeight / 2;
    for (var i = 0; i < measured.children.length; i++) {
      final child = measured.children[i];
      final childCenterY = currentY + child.totalHeight / 2;
      final horizontal =
          measured.size.width / 2 + nodeHorizontalGap + child.size.width / 2;
      final childCenterX = isLeft
          ? center.dx - horizontal
          : center.dx + horizontal;
      _layoutSubtree(
        child,
        Offset(childCenterX, childCenterY),
        isLeft,
        branchIndex,
        measured.node.id,
        addNode,
      );
      currentY += child.totalHeight;
      if (i < measured.children.length - 1) {
        currentY += nodeVerticalGap;
      }
    }
  }

  double _stackHeight(List<_MeasuredNode> nodes) {
    if (nodes.isEmpty) {
      return 0;
    }
    var total = 0.0;
    for (var i = 0; i < nodes.length; i++) {
      if (i > 0) {
        total += nodeVerticalGap;
      }
      total += nodes[i].totalHeight;
    }
    return total;
  }
}

class _Branch {
  _Branch(this.node, this.index);

  final _MeasuredNode node;
  final int index;
}

class _MeasuredNode {
  _MeasuredNode({
    required this.node,
    required this.size,
    required this.totalHeight,
    required this.childrenHeight,
    required this.lines,
    required this.children,
  });

  final MindMapNode node;
  final Size size;
  final double totalHeight;
  final double childrenHeight;
  final List<String> lines;
  final List<_MeasuredNode> children;
}
