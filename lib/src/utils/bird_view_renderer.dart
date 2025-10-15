import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../layout/mind_map_layout.dart';
import '../theme/app_colors.dart';
import 'constants.dart';

class BirdViewProjection {
  const BirdViewProjection({
    required this.scale,
    required this.offset,
    required this.paddedBounds,
  });

  final double scale;
  final Offset offset;
  final Rect paddedBounds;

  Offset transform(Offset point) =>
      Offset(point.dx * scale + offset.dx, point.dy * scale + offset.dy);

  Rect transformRect(Rect rect) =>
      Rect.fromPoints(transform(rect.topLeft), transform(rect.bottomRight));

  Offset untransform(Offset point) =>
      Offset((point.dx - offset.dx) / scale, (point.dy - offset.dy) / scale);
}

class BirdViewRenderer {
  const BirdViewRenderer._();

  static const double _padding = 48;

  static BirdViewProjection project({
    required Size size,
    required Rect bounds,
  }) {
    final padded = bounds.inflate(_padding);
    final double width = padded.width <= 0 ? 1.0 : padded.width;
    final double height = padded.height <= 0 ? 1.0 : padded.height;
    final double scale = min(size.width / width, size.height / height);
    final double offsetX =
        -padded.left * scale + (size.width - width * scale) / 2;
    final double offsetY =
        -padded.top * scale + (size.height - height * scale) / 2;
    return BirdViewProjection(
      scale: scale,
      offset: Offset(offsetX, offsetY),
      paddedBounds: padded,
    );
  }

  static void paint({
    required Canvas canvas,
    required Size size,
    required Map<String, NodeRenderData> nodes,
    required Rect bounds,
    String? selectedNodeId,
    Rect? viewportRect,
    BirdViewProjection? projection,
  }) {
    if (nodes.isEmpty) {
      return;
    }

    final BirdViewProjection proj =
        projection ?? project(size: size, bounds: bounds);
    final double normalizedScale = sqrt(max(proj.scale, 0.0001));
    final double connectionWidth = (1.2 * normalizedScale).clamp(1.0, 2.8);
    final double nodeRadius = (3.4 * normalizedScale).clamp(2.6, 6.0);
    final double selectedRadius = nodeRadius * 1.6;

    final Paint connectorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = connectionWidth;

    for (final entry in nodes.entries) {
      final data = entry.value;
      final parentId = data.parentId;
      if (parentId == null) {
        continue;
      }
      final parent = nodes[parentId];
      if (parent == null) {
        continue;
      }
      final color =
          branchColors[(data.branchIndex >= 0 ? data.branchIndex : 0) %
              branchColors.length];
      connectorPaint.color = color.withOpacity(0.45);

      final start = Offset(
        parent.center.dx +
            (data.isLeft ? -parent.size.width / 2 : parent.size.width / 2),
        parent.center.dy,
      );
      final end = Offset(
        data.center.dx +
            (data.isLeft ? data.size.width / 2 : -data.size.width / 2),
        data.center.dy,
      );
      final controlOffset = data.isLeft
          ? -nodeHorizontalGap / 2
          : nodeHorizontalGap / 2;
      final control1 = Offset(start.dx + controlOffset, start.dy);
      final control2 = Offset(end.dx - controlOffset, end.dy);
      final Offset startCanvas = proj.transform(start);
      final Offset control1Canvas = proj.transform(control1);
      final Offset control2Canvas = proj.transform(control2);
      final Offset endCanvas = proj.transform(end);
      final Path path = Path()
        ..moveTo(startCanvas.dx, startCanvas.dy)
        ..cubicTo(
          control1Canvas.dx,
          control1Canvas.dy,
          control2Canvas.dx,
          control2Canvas.dy,
          endCanvas.dx,
          endCanvas.dy,
        );
      canvas.drawPath(path, connectorPaint);
    }

    final Paint fillPaint = Paint()
      ..color = AppColors.cloudWhite
      ..style = PaintingStyle.fill;
    final Paint strokePaint = Paint()..style = PaintingStyle.stroke;
    final Paint highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (1.6 * normalizedScale).clamp(1.2, 3.2)
      ..color = AppColors.lavenderLift.withOpacity(0.8);

    for (final data in nodes.values) {
      final color =
          branchColors[(data.branchIndex >= 0 ? data.branchIndex : 0) %
              branchColors.length];
      final center = proj.transform(data.center);
      strokePaint
        ..color = color.withOpacity(0.85)
        ..strokeWidth = (1.2 * normalizedScale).clamp(1.0, 2.4);
      final bool isSelected = data.node.id == selectedNodeId;
      final double radius = isSelected ? selectedRadius : nodeRadius;
      canvas.drawCircle(center, radius, fillPaint);
      canvas.drawCircle(center, radius, strokePaint);
      if (isSelected) {
        canvas.drawCircle(center, radius + 3, highlightPaint);
      }
    }

    if (viewportRect != null) {
      final Rect projected = proj.transformRect(viewportRect);
      final Paint viewportPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (1.4 * normalizedScale).clamp(1.2, 2.4)
        ..color = AppColors.graphSlate.withOpacity(0.7);
      final Paint viewportFill = Paint()
        ..style = PaintingStyle.fill
        ..color = AppColors.graphSlate.withOpacity(0.08);
      canvas.drawRect(projected, viewportFill);
      canvas.drawRect(projected, viewportPaint);
    }
  }

  static Future<Uint8List?> renderPreview({
    required MindMapLayoutResult layout,
    double dimension = 384,
  }) async {
    if (layout.isEmpty) {
      return null;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, dimension, dimension));
    canvas.drawColor(AppColors.cloudWhite, BlendMode.src);
    final projection = project(
      size: Size(dimension, dimension),
      bounds: layout.bounds,
    );
    paint(
      canvas: canvas,
      size: Size(dimension, dimension),
      nodes: layout.nodes,
      bounds: layout.bounds,
      projection: projection,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(dimension.round(), dimension.round());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}
