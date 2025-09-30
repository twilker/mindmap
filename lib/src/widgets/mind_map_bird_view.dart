import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/mind_map_layout.dart';
import '../state/layout_snapshot.dart';
import '../state/mind_map_state.dart';
import '../utils/bird_view_renderer.dart';
import '../utils/constants.dart';

class MindMapBirdView extends ConsumerWidget {
  const MindMapBirdView({super.key, this.size = const Size(220, 220)});

  final Size size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(mindMapLayoutSnapshotProvider);
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
        width: size.width,
        height: size.height,
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
                  child: _BirdViewCanvas(
                    snapshot: effectiveSnapshot,
                    selectedNodeId: selectedId,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BirdViewCanvas extends StatelessWidget {
  const _BirdViewCanvas({this.snapshot, this.selectedNodeId});

  final MindMapLayoutSnapshot? snapshot;
  final String? selectedNodeId;

  @override
  Widget build(BuildContext context) {
    final effectiveSnapshot = snapshot;
    if (effectiveSnapshot == null || effectiveSnapshot.nodes.isEmpty) {
      return const _BirdViewPlaceholder();
    }
    return CustomPaint(
      painter: _BirdViewPainter(
        snapshot: effectiveSnapshot,
        selectedNodeId: selectedNodeId,
      ),
    );
  }
}

class _BirdViewPainter extends CustomPainter {
  _BirdViewPainter({required this.snapshot, required this.selectedNodeId});

  final MindMapLayoutSnapshot snapshot;
  final String? selectedNodeId;

  @override
  void paint(Canvas canvas, Size size) {
    BirdViewRenderer.paint(
      canvas: canvas,
      size: size,
      nodes: snapshot.nodes,
      bounds: snapshot.bounds,
      selectedNodeId: selectedNodeId,
    );
  }

  @override
  bool shouldRepaint(covariant _BirdViewPainter oldDelegate) {
    return oldDelegate.snapshot != snapshot ||
        oldDelegate.selectedNodeId != selectedNodeId;
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
