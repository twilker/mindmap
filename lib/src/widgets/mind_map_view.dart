import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../layout/mind_map_layout.dart';
import '../state/mind_map_state.dart';
import '../state/layout_snapshot.dart';
import '../utils/constants.dart';
import 'node_card.dart';

class MindMapViewController {
  _MindMapViewState? _state;

  void _attach(_MindMapViewState state) {
    _state = state;
  }

  void _detach(_MindMapViewState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  static const double _zoomInFactor = 1.5;
  static const double _zoomOutFactor = 1 / _zoomInFactor;

  void zoomIn() => _state?._handleExternalZoom(_zoomInFactor);

  void zoomOut() => _state?._handleExternalZoom(_zoomOutFactor);

  void resetView() => _state?._resetView();

  void focusOnNode(String id, {bool preferTopHalf = false}) =>
      _state?._focusOnNode(id, preferTopHalf: preferTopHalf);
}

class MindMapView extends ConsumerStatefulWidget {
  const MindMapView({super.key, this.controller});

  final MindMapViewController? controller;

  @override
  ConsumerState<MindMapView> createState() => _MindMapViewState();
}

class _MindMapViewState extends ConsumerState<MindMapView>
    with SingleTickerProviderStateMixin {
  late final TransformationController _controller;
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;
  int _lastAutoFitVersion = -1;
  Matrix4? _homeTransform;
  Size? _viewportSize;
  String? _pendingFocusNodeId;
  bool _pendingPreferTopHalf = false;
  double _keyboardInset = 0;
  String? _editingNodeId;
  bool _editingPreferTopHalf = false;
  Offset? _pendingDoubleTapPosition;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant MindMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _animation?.removeListener(_applyAnimatedValue);
    _animationController.dispose();
    _controller.dispose();
    ref.read(mindMapLayoutSnapshotProvider.notifier).state = null;
    super.dispose();
  }

  void _applyAnimatedValue() {
    if (_animation != null) {
      _controller.value = _animation!.value;
    }
  }

  void _animateTo(Matrix4 target) {
    _animation?.removeListener(_applyAnimatedValue);
    _animationController.stop();
    final tween = Matrix4Tween(begin: _controller.value, end: target);
    _animation = tween.animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animation!.addListener(_applyAnimatedValue);
    _animationController
      ..reset()
      ..forward();
  }

  void _zoomBy(double factor, Size viewportSize) {
    final current = _controller.value.clone();
    final scale = current.getMaxScaleOnAxis();
    final targetScale = (scale * factor).clamp(zoomMinScale, zoomMaxScale);
    final appliedFactor = targetScale / scale;
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final matrix = Matrix4.identity()
      ..translateByVector3(vm.Vector3(center.dx, center.dy, 0))
      ..scaleByVector3(vm.Vector3(appliedFactor, appliedFactor, 1))
      ..translateByVector3(vm.Vector3(-center.dx, -center.dy, 0));
    _controller.value = matrix.multiplied(current);
  }

  void _resetView() {
    if (_homeTransform != null) {
      _animateTo(_homeTransform!.clone());
    }
  }

  void _handleExternalZoom(double factor) {
    final viewportSize = _viewportSize;
    if (viewportSize == null) {
      return;
    }
    _zoomBy(factor, viewportSize);
  }

  void _zoomAt(Offset focalPoint, double factor) {
    final viewportSize = _viewportSize;
    if (viewportSize == null) {
      return;
    }
    final current = _controller.value.clone();
    final scale = current.getMaxScaleOnAxis();
    final targetScale = (scale * factor).clamp(zoomMinScale, zoomMaxScale);
    final appliedFactor = targetScale / scale;
    if (appliedFactor == 1) {
      return;
    }
    final matrix = Matrix4.identity()
      ..translate(focalPoint.dx, focalPoint.dy)
      ..scale(appliedFactor, appliedFactor, 1)
      ..translate(-focalPoint.dx, -focalPoint.dy);
    _controller.value = matrix.multiplied(current);
  }

  void _focusOnNode(String id, {bool preferTopHalf = false}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingFocusNodeId = id;
      _pendingPreferTopHalf = preferTopHalf;
    });
  }

  void _handleEditingChanged(
    String nodeId,
    bool isEditing, {
    bool preferTopHalf = false,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (isEditing) {
        _editingNodeId = nodeId;
        _editingPreferTopHalf = preferTopHalf;
      } else if (_editingNodeId == nodeId) {
        _editingNodeId = null;
        _editingPreferTopHalf = false;
      }
    });
  }

  void _handleBackgroundTap() {
    if (_editingNodeId != null) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _handleBackgroundDoubleTap(Offset localPosition) {
    _pendingDoubleTapPosition = null;
    _handleBackgroundTap();
    _zoomAt(localPosition, MindMapViewController._zoomInFactor);
  }

  @override
  Widget build(BuildContext context) {
    final mindMapState = ref.watch(mindMapProvider);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final previousInset = _keyboardInset;
    final bottomInset = viewInsets.bottom;
    if (previousInset != bottomInset) {
      if (bottomInset > 0 &&
          previousInset <= 0 &&
          _editingNodeId != null &&
          _editingPreferTopHalf) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _editingNodeId == null) {
            return;
          }
          _focusOnNode(_editingNodeId!, preferTopHalf: true);
        });
      }
      _keyboardInset = bottomInset;
    }
    final layoutEngine = MindMapLayoutEngine(
      textStyle: textStyle,
      textScaler: MediaQuery.textScalerOf(context),
    );
    final layout = layoutEngine.layout(mindMapState.root);
    final origin = Offset(
      -layout.bounds.left + boundsMargin,
      -layout.bounds.top + boundsMargin,
    );
    final contentSize = Size(
      layout.bounds.width + boundsMargin * 2,
      layout.bounds.height + boundsMargin * 2,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mindMapProvider.notifier).updateContentBounds(layout.bounds);
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        _viewportSize = viewportSize;
        _maybeAutoFit(mindMapState, layout, origin, viewportSize);
        _scheduleLayoutSnapshotUpdate(layout);
        _maybeFocusPending(layout, origin, viewportSize);

        return _buildInteractiveViewer(layout, origin, contentSize);
      },
    );
  }

  void _scheduleLayoutSnapshotUpdate(MindMapLayoutResult layout) {
    final snapshot = layout.isEmpty
        ? null
        : MindMapLayoutSnapshot(nodes: layout.nodes, bounds: layout.bounds);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(mindMapLayoutSnapshotProvider.notifier).state = snapshot;
    });
  }

  Widget _buildInteractiveViewer(
    MindMapLayoutResult layout,
    Offset origin,
    Size contentSize,
  ) {
    final selectedId = ref.watch(
      mindMapProvider.select((s) => s.selectedNodeId),
    );
    final nodes = layout.nodes.values.toList();

    bool isPointOnNode(Offset localPosition) {
      final inverse = Matrix4.inverted(_controller.value);
      final scenePoint = MatrixUtils.transformPoint(inverse, localPosition);
      for (final data in nodes) {
        final rect = Rect.fromLTWH(
          data.topLeft.dx + origin.dx,
          data.topLeft.dy + origin.dy,
          data.size.width,
          data.size.height,
        );
        if (rect.contains(scenePoint)) {
          return true;
        }
      }
      return false;
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _handleBackgroundTap,
      onDoubleTapDown: (details) {
        if (isPointOnNode(details.localPosition)) {
          _pendingDoubleTapPosition = null;
          return;
        }
        _pendingDoubleTapPosition = details.localPosition;
      },
      onDoubleTap: () {
        final position = _pendingDoubleTapPosition;
        if (position != null) {
          _handleBackgroundDoubleTap(position);
        }
      },
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: zoomMinScale,
        maxScale: zoomMaxScale,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        constrained: false,
        child: SizedBox(
          width: max(contentSize.width, 1),
          height: max(contentSize.height, 1),
          child: Stack(
            children: [
              CustomPaint(
                size: contentSize,
                painter: _ConnectorPainter(layout: layout, origin: origin),
              ),
              for (final data in nodes)
                Positioned(
                  left: data.topLeft.dx + origin.dx,
                  top: data.topLeft.dy + origin.dy,
                  child: SizedBox(
                    width: data.size.width,
                    height: data.size.height,
                    child: MindMapNodeCard(
                      data: data,
                      isSelected: data.node.id == selectedId,
                      accentColor:
                          branchColors[(data.branchIndex >= 0
                                  ? data.branchIndex
                                  : 0) %
                              branchColors.length],
                      onRequestFocusOnNode: widget.controller == null
                          ? null
                          : (id, {bool preferTopHalf = false}) => widget
                                .controller!
                                .focusOnNode(id, preferTopHalf: preferTopHalf),
                      onEditingChanged:
                          (nodeId, isEditing, {bool preferTopHalf = false}) {
                            _handleEditingChanged(
                              nodeId,
                              isEditing,
                              preferTopHalf: preferTopHalf,
                            );
                          },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _maybeAutoFit(
    MindMapState state,
    MindMapLayoutResult layout,
    Offset origin,
    Size viewportSize,
  ) {
    if (_lastAutoFitVersion == state.autoFitVersion || layout.isEmpty) {
      return;
    }
    _lastAutoFitVersion = state.autoFitVersion;
    final padded = layout.bounds.inflate(boundsMargin).shift(origin);
    final paddedWidth = padded.width <= 0 ? 1.0 : padded.width;
    final paddedHeight = padded.height <= 0 ? 1.0 : padded.height;
    final scaleX = viewportSize.width / paddedWidth;
    final scaleY = viewportSize.height / paddedHeight;
    final scale = min(scaleX, scaleY).clamp(zoomMinScale, zoomMaxScale);
    final offsetX =
        -padded.left * scale + (viewportSize.width - paddedWidth * scale) / 2;
    final offsetY =
        -padded.top * scale + (viewportSize.height - paddedHeight * scale) / 2;
    final matrix = Matrix4.identity()
      ..translateByVector3(vm.Vector3(offsetX, offsetY, 0))
      ..scaleByVector3(vm.Vector3(scale, scale, 1));
    _homeTransform = matrix.clone();
    _animateTo(matrix);
  }

  void _maybeFocusPending(
    MindMapLayoutResult layout,
    Offset origin,
    Size viewportSize,
  ) {
    final targetId = _pendingFocusNodeId;
    if (targetId == null || layout.isEmpty) {
      return;
    }
    final data = layout.nodes[targetId];
    if (data == null) {
      _pendingFocusNodeId = null;
      return;
    }
    final matrix = _controller.value.clone();
    final rect = Rect.fromCenter(
      center: data.center + origin,
      width: data.size.width,
      height: data.size.height,
    );
    final transformedRect = MatrixUtils.transformRect(matrix, rect);
    final preferTopHalf = _pendingPreferTopHalf;
    _pendingFocusNodeId = null;
    _pendingPreferTopHalf = false;
    final delta = _computeFocusDelta(
      transformedRect,
      viewportSize,
      preferTopHalf,
    );
    if (delta == Offset.zero) {
      return;
    }
    final translation = matrix.getTranslation();
    matrix.setTranslationRaw(
      translation.x + delta.dx,
      translation.y + delta.dy,
      translation.z,
    );
    _animateTo(matrix);
  }

  Offset _computeFocusDelta(Rect rect, Size viewportSize, bool preferTopHalf) {
    var dx = 0.0;
    var dy = 0.0;
    Rect adjusted = rect;

    if (viewportSize.width <= focusViewportMargin * 2) {
      dx = viewportSize.width / 2 - adjusted.center.dx;
      adjusted = adjusted.shift(Offset(dx, 0));
    } else {
      if (adjusted.left < focusViewportMargin) {
        final delta = focusViewportMargin - adjusted.left;
        dx += delta;
        adjusted = adjusted.shift(Offset(delta, 0));
      }
      if (adjusted.right > viewportSize.width - focusViewportMargin) {
        final delta = viewportSize.width - focusViewportMargin - adjusted.right;
        dx += delta;
        adjusted = adjusted.shift(Offset(delta, 0));
      }
    }

    final bottomInset = _keyboardInset;
    final visibleBottom = max(
      viewportSize.height - bottomInset,
      focusViewportMargin,
    );
    final topLimit = focusViewportMargin;
    final bottomLimit = visibleBottom - focusViewportMargin;

    if (bottomLimit <= topLimit) {
      final targetCenterY = (visibleBottom + topLimit) / 2;
      final delta = targetCenterY - adjusted.center.dy;
      dy += delta;
      adjusted = adjusted.shift(Offset(0, delta));
    } else {
      if (adjusted.top < topLimit) {
        final delta = topLimit - adjusted.top;
        dy += delta;
        adjusted = adjusted.shift(Offset(0, delta));
      }
      if (adjusted.bottom > bottomLimit) {
        final delta = bottomLimit - adjusted.bottom;
        dy += delta;
        adjusted = adjusted.shift(Offset(0, delta));
      }
    }

    if (preferTopHalf && bottomInset > 0) {
      final targetCenterY = visibleBottom / 2;
      if (adjusted.center.dy > targetCenterY) {
        final delta = targetCenterY - adjusted.center.dy;
        dy += delta;
        adjusted = adjusted.shift(Offset(0, delta));
      }
    }

    if (dx.abs() < 0.5 && dy.abs() < 0.5) {
      return Offset.zero;
    }
    return Offset(dx, dy);
  }
}

class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter({required this.layout, required this.origin});

  final MindMapLayoutResult layout;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = layout.nodes;
    for (final entry in nodes.entries) {
      final data = entry.value;
      if (data.parentId == null) {
        continue;
      }
      final parent = nodes[data.parentId];
      if (parent == null) {
        continue;
      }
      final color =
          branchColors[(data.branchIndex >= 0 ? data.branchIndex : 0) %
              branchColors.length];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = color.withValues(alpha: color.a * 0.85);

      final start = Offset(
        parent.center.dx +
            origin.dx +
            (data.isLeft ? -parent.size.width / 2 : parent.size.width / 2),
        parent.center.dy + origin.dy,
      );
      final end = Offset(
        data.center.dx +
            origin.dx +
            (data.isLeft ? data.size.width / 2 : -data.size.width / 2),
        data.center.dy + origin.dy,
      );
      final controlOffset = data.isLeft
          ? -nodeHorizontalGap / 2
          : nodeHorizontalGap / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + controlOffset,
          start.dy,
          end.dx - controlOffset,
          end.dy,
          end.dx,
          end.dy,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter oldDelegate) {
    return oldDelegate.layout != layout || oldDelegate.origin != origin;
  }
}
