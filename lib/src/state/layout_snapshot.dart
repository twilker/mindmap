import 'dart:collection';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/mind_map_layout.dart';

final mindMapLayoutSnapshotProvider = StateProvider<MindMapLayoutSnapshot?>(
  (ref) => null,
);

class MindMapLayoutSnapshot {
  MindMapLayoutSnapshot({
    required Map<String, NodeRenderData> nodes,
    required this.bounds,
  }) : nodes = UnmodifiableMapView(nodes);

  final Map<String, NodeRenderData> nodes;
  final Rect bounds;
}
