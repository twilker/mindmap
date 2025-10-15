import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MindMapViewportSnapshot {
  MindMapViewportSnapshot({
    required this.viewportSize,
    required this.transform,
    required this.origin,
  });

  final Size viewportSize;
  final Matrix4 transform;
  final Offset origin;
}

final mindMapViewportProvider = StateProvider<MindMapViewportSnapshot?>(
  (ref) => null,
);
