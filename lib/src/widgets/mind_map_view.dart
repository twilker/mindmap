import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../layout/mind_map_layout.dart';
import '../state/mind_map_state.dart';
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

  void zoomIn() => _state?._handleExternalZoom(1.25);

  void zoomOut() => _state?._handleExternalZoom(0.8);

  void resetView() => _state?._resetView();
}

class MindMapView extends ConsumerStatefulWidget {
  const MindMapView({super.key, this.controller});

  final MindMapViewController? controller;

  @override
  ConsumerState<MindMapView> createState() => _MindMapViewState();
}

class _MindMapViewState extends ConsumerState<MindMapView> with SingleTickerProviderStateMixin {
  late final TransformationController _controller;
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;
  int _lastAutoFitVersion = -1;
  Matrix4? _homeTransform;
  Size? _viewportSize;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
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
    _animation = tween.animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
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

  @override
  Widget build(BuildContext context) {
    final mindMapState = ref.watch(mindMapProvider);
    final layoutEngine = MindMapLayoutEngine(
      textStyle: textStyle,
      textScaler: MediaQuery.textScalerOf(context),
    );
    final layout = layoutEngine.layout(mindMapState.root);
    final origin = Offset(-layout.bounds.left + boundsMargin, -layout.bounds.top + boundsMargin);
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
        _maybeAutoFit(
          mindMapState,
          layout,
          origin,
          viewportSize,
        );

        return _buildInteractiveViewer(layout, origin, contentSize);
      },
    );
  }

  Widget _buildInteractiveViewer(MindMapLayoutResult layout, Offset origin, Size contentSize) {
    final selectedId = ref.watch(mindMapProvider.select((s) => s.selectedNodeId));
    final nodes = layout.nodes.values.toList();

    return InteractiveViewer(
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
                    accentColor: branchColors[(data.branchIndex >= 0 ? data.branchIndex : 0) % branchColors.length],
                  ),
                ),
              ),
          ],
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
      final color = branchColors[(data.branchIndex >= 0 ? data.branchIndex : 0) % branchColors.length];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = color.withValues(alpha: color.a * 0.85);

      final start = Offset(
        parent.center.dx + origin.dx + (data.isLeft ? -parent.size.width / 2 : parent.size.width / 2),
        parent.center.dy + origin.dy,
      );
      final end = Offset(
        data.center.dx + origin.dx + (data.isLeft ? data.size.width / 2 : -data.size.width / 2),
        data.center.dy + origin.dy,
      );
      final controlOffset = data.isLeft ? -nodeHorizontalGap / 2 : nodeHorizontalGap / 2;
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
