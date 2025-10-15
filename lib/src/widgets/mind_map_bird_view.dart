import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../layout/mind_map_layout.dart';
import '../state/layout_snapshot.dart';
import '../state/mind_map_state.dart';
import '../state/mind_map_viewport.dart';
import '../utils/bird_view_renderer.dart';
import '../utils/constants.dart';
import 'mind_map_view.dart';

class MindMapBirdView extends ConsumerStatefulWidget {
  const MindMapBirdView({
    super.key,
    required this.controller,
    this.size = const Size(220, 220),
  });

  final MindMapViewController controller;
  final Size size;

  @override
  ConsumerState<MindMapBirdView> createState() => _MindMapBirdViewState();
}

class _MindMapBirdViewState extends ConsumerState<MindMapBirdView> {
  Rect? _viewportRect;
  BirdViewProjection? _projection;
  Offset? _dragOffset;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(mindMapLayoutSnapshotProvider);
    final viewportSnapshot = ref.watch(mindMapViewportProvider);
    final mapState = ref.watch(mindMapProvider);
    final selectedId = mapState.selectedNodeId;
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    MindMapLayoutSnapshot? effectiveSnapshot = snapshot;
    if (effectiveSnapshot == null) {
      final layout = MindMapLayoutEngine(
        textStyle: textStyle,
        textScaler: textScaler,
      ).layout(mapState.root);
      if (!layout.isEmpty) {
        effectiveSnapshot = MindMapLayoutSnapshot(
          nodes: layout.nodes,
          bounds: layout.bounds,
        );
      }
    }

    return Material(
      elevation: 8,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(appCornerRadius),
      child: Container(
        width: widget.size.width,
        height: widget.size.height,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(appCornerRadius),
          border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bird view',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(appCornerRadius - 2),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.surface,
                        theme.colorScheme.surfaceVariant.withOpacity(0.4),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: _buildCanvas(
                    context,
                    effectiveSnapshot,
                    viewportSnapshot,
                    selectedId,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas(
    BuildContext context,
    MindMapLayoutSnapshot? snapshot,
    MindMapViewportSnapshot? viewportSnapshot,
    String? selectedId,
  ) {
    final effectiveSnapshot = snapshot;
    if (effectiveSnapshot == null || effectiveSnapshot.nodes.isEmpty) {
      return const _BirdViewPlaceholder();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        final projection = BirdViewRenderer.project(
          size: canvasSize,
          bounds: effectiveSnapshot.bounds,
        );
        final viewportRect = viewportSnapshot == null
            ? null
            : _extractViewportRect(viewportSnapshot);
        _projection = projection;
        _viewportRect = viewportRect;

        final painter = _BirdViewPainter(
          snapshot: effectiveSnapshot,
          selectedNodeId: selectedId,
          projection: projection,
          viewportRect: viewportRect,
        );

        return MouseRegion(
          cursor: viewportRect != null
              ? SystemMouseCursors.move
              : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: viewportRect != null
                ? (details) => _handleTapDown(details)
                : null,
            onPanStart: viewportRect != null
                ? (details) => _handlePanStart(details)
                : null,
            onPanUpdate: viewportRect != null
                ? (details) => _handlePanUpdate(details)
                : null,
            onPanEnd: viewportRect != null ? (_) => _handlePanEnd() : null,
            onTapCancel: viewportRect != null ? _handlePanEnd : null,
            child: SizedBox.expand(child: CustomPaint(painter: painter)),
          ),
        );
      },
    );
  }

  void _handleTapDown(TapDownDetails details) {
    final projection = _projection;
    final rect = _viewportRect;
    if (projection == null || rect == null) {
      return;
    }
    final layoutPoint = projection.untransform(details.localPosition);
    _moveViewport(layoutPoint, rect.size, projection);
  }

  void _handlePanStart(DragStartDetails details) {
    final projection = _projection;
    final rect = _viewportRect;
    if (projection == null || rect == null) {
      return;
    }
    final layoutPoint = projection.untransform(details.localPosition);
    if (!rect.inflate(12).contains(layoutPoint)) {
      _dragOffset = null;
      return;
    }
    _dragOffset = layoutPoint - rect.center;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final projection = _projection;
    final rect = _viewportRect;
    if (projection == null || rect == null) {
      return;
    }
    final layoutPoint = projection.untransform(details.localPosition);
    final center = _dragOffset == null
        ? layoutPoint
        : layoutPoint - _dragOffset!;
    _moveViewport(center, rect.size, projection);
  }

  void _handlePanEnd() {
    _dragOffset = null;
  }

  void _moveViewport(
    Offset targetCenter,
    Size rectSize,
    BirdViewProjection projection,
  ) {
    final clampedCenter = _clampCenter(targetCenter, rectSize, projection);
    if (_viewportRect?.center == clampedCenter) {
      return;
    }
    widget.controller.moveViewportToLayoutCenter(clampedCenter);
  }

  Offset _clampCenter(
    Offset center,
    Size rectSize,
    BirdViewProjection projection,
  ) {
    final double halfWidth = rectSize.width / 2;
    final double halfHeight = rectSize.height / 2;
    final Rect bounds = projection.paddedBounds;
    final double minX = bounds.left + halfWidth;
    final double maxX = bounds.right - halfWidth;
    final double minY = bounds.top + halfHeight;
    final double maxY = bounds.bottom - halfHeight;
    final double clampedX = (minX <= maxX)
        ? center.dx.clamp(minX, maxX)
        : bounds.center.dx;
    final double clampedY = (minY <= maxY)
        ? center.dy.clamp(minY, maxY)
        : bounds.center.dy;
    return Offset(clampedX, clampedY);
  }

  Rect? _extractViewportRect(MindMapViewportSnapshot snapshot) {
    Matrix4 inverse;
    try {
      inverse = Matrix4.inverted(snapshot.transform);
    } catch (_) {
      return null;
    }
    final Offset topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final Offset bottomRight = MatrixUtils.transformPoint(
      inverse,
      Offset(snapshot.viewportSize.width, snapshot.viewportSize.height),
    );
    final double left = math.min(topLeft.dx, bottomRight.dx);
    final double right = math.max(topLeft.dx, bottomRight.dx);
    final double top = math.min(topLeft.dy, bottomRight.dy);
    final double bottom = math.max(topLeft.dy, bottomRight.dy);
    final Rect childRect = Rect.fromLTRB(left, top, right, bottom);
    return childRect.shift(-snapshot.origin);
  }
}

class _BirdViewPainter extends CustomPainter {
  _BirdViewPainter({
    required this.snapshot,
    required this.selectedNodeId,
    required this.projection,
    this.viewportRect,
  });

  final MindMapLayoutSnapshot snapshot;
  final String? selectedNodeId;
  final BirdViewProjection projection;
  final Rect? viewportRect;

  @override
  void paint(Canvas canvas, Size size) {
    BirdViewRenderer.paint(
      canvas: canvas,
      size: size,
      nodes: snapshot.nodes,
      bounds: snapshot.bounds,
      selectedNodeId: selectedNodeId,
      viewportRect: viewportRect,
      projection: projection,
    );
  }

  @override
  bool shouldRepaint(covariant _BirdViewPainter oldDelegate) {
    return oldDelegate.snapshot != snapshot ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.viewportRect != viewportRect ||
        oldDelegate.projection.scale != projection.scale ||
        oldDelegate.projection.offset != projection.offset;
  }
}

class _BirdViewPlaceholder extends StatelessWidget {
  const _BirdViewPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.travel_explore_outlined,
            color: theme.colorScheme.onSurface.withOpacity(0.24),
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            'Nothing to preview yet',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
