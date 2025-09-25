import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/mind_map_layout.dart';

final mindMapLayoutSnapshotProvider = StateProvider<MindMapLayoutSnapshot?>(
  (ref) => null,
);

class MindMapLayoutSnapshot {
  MindMapLayoutSnapshot({required Map<String, NodeRenderData> nodes})
    : nodes = UnmodifiableMapView(nodes);

  final Map<String, NodeRenderData> nodes;
}
