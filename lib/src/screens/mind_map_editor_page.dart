import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/file_exporter.dart';

import '../layout/mind_map_layout.dart';
import '../state/current_map.dart';
import '../state/mind_map_state.dart';
import '../state/mind_map_storage.dart';
import '../state/mind_map_preview_storage.dart';
import '../utils/bird_view_renderer.dart';
import '../utils/constants.dart';
import '../utils/svg_exporter.dart';
import '../utils/touch_mode.dart';
import '../widgets/mind_map_bird_view.dart';
import '../widgets/mind_map_view.dart';
import '../widgets/node_details_dialog.dart';
import '../theme/app_colors.dart';
import '../sync/cloud_sync_notifier.dart';
import '../widgets/cloud_sync_status.dart';

class MindMapEditorPage extends ConsumerStatefulWidget {
  const MindMapEditorPage({super.key, required this.mapName});

  final String mapName;

  @override
  ConsumerState<MindMapEditorPage> createState() => _MindMapEditorPageState();
}

class _MindMapEditorPageState extends ConsumerState<MindMapEditorPage> {
  final MindMapViewController _viewController = MindMapViewController();
  late final ProviderSubscription<String?> _mapNameSubscription;
  late final ProviderSubscription<MindMapState> _mindMapSubscription;
  String? _currentMapName;
  String? _lastSavedDocument;
  String? _pendingDocument;
  MindMapState? _pendingState;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentMapName = widget.mapName;
    ref.read(currentMapNameProvider.notifier).state = widget.mapName;
    _lastSavedDocument = ref.read(mindMapProvider).document;
    _mapNameSubscription = ref.listenManual<String?>(currentMapNameProvider, (
      previous,
      next,
    ) {
      _currentMapName = next;
    });
    _mindMapSubscription = ref.listenManual<MindMapState>(mindMapProvider, (
      previous,
      next,
    ) {
      _scheduleSave(next);
    });
  }

  @override
  void dispose() {
    _mapNameSubscription.close();
    _mindMapSubscription.close();
    _currentMapName = null;
    ref.read(currentMapNameProvider.notifier).state = null;
    super.dispose();
  }

  void _scheduleSave(MindMapState next) {
    final name = _currentMapName;
    if (name == null) {
      return;
    }
    if (next.document == _lastSavedDocument ||
        next.document == _pendingDocument) {
      return;
    }
    _pendingDocument = next.document;
    _pendingState = next;
    if (_saving) {
      return;
    }
    _saving = true;
    unawaited(_runSaveLoop());
  }

  Future<void> _runSaveLoop() async {
    while (_pendingDocument != null) {
      final name = _currentMapName;
      if (name == null) {
        break;
      }
      final pending = _pendingDocument!;
      final pendingState = _pendingState;
      _pendingDocument = null;
      _pendingState = null;
      Uint8List? preview;
      if (pendingState != null) {
        preview = await _generateBirdViewPreview(pendingState);
      }
      try {
        await ref
            .read(savedMapsProvider.notifier)
            .save(name, pending, silent: true, preview: preview);
        await ref
            .read(cloudSyncNotifierProvider.notifier)
            .enqueueUpdate(name, pending);
        ref.invalidate(mindMapPreviewProvider(name));
        _lastSavedDocument = pending;
      } catch (err) {
        if (mounted) {
          _showMessage('Failed to save "$name": $err');
        }
        _pendingDocument ??= pending;
        if (_pendingState == null && pendingState != null) {
          _pendingState = pendingState;
        }
        break;
      }
    }
    _saving = false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editNodeDetails(String nodeId) async {
    final notifier = ref.read(mindMapProvider.notifier);
    final node = notifier.nodeById(nodeId);
    if (node == null) {
      return;
    }
    notifier.selectNode(nodeId);
    final result = await showNodeDetailsEditorDialog(
      context,
      title: 'Edit details',
      initialValue: node.details,
    );
    if (result != null) {
      notifier.updateNodeDetails(nodeId, result);
    }
  }

  void _exportMarkdown() {
    final markdown = ref.read(mindMapProvider.notifier).exportMarkdown();
    unawaited(_exportFile('mindmap.txt', markdown, 'text/plain'));
  }

  void _exportSvg() {
    final state = ref.read(mindMapProvider);
    final layout = MindMapLayoutEngine(
      textStyle: textStyle,
      textScaler: MediaQuery.textScalerOf(context),
    ).layout(state.root);
    final exporter = SvgExporter(
      layout: layout,
      bounds: state.lastContentBounds ?? layout.bounds,
    );
    final svg = exporter.build();
    unawaited(_exportFile('mindmap.svg', svg, 'image/svg+xml'));
  }

  Future<void> _exportFile(
    String filename,
    String content,
    String mimeType,
  ) async {
    try {
      await saveTextFile(filename, content, mimeType);
    } catch (err) {
      if (!mounted) return;
      _showMessage('Failed to export $filename: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mindMapProvider);
    _lastSavedDocument ??= state.document;
    final mapName = ref.watch(currentMapNameProvider) ?? widget.mapName;
    final isTouchOnly = TouchModeResolver.isTouchOnly(context);

    final stackChildren = <Widget>[
      Positioned.fill(
        child: MindMapView(
          controller: _viewController,
          touchOnlyMode: isTouchOnly,
        ),
      ),
    ];

    if (!isTouchOnly) {
      stackChildren
        ..add(_buildBirdViewOverlay(isTouchOnly))
        ..add(_buildTopControls(mapName))
        ..add(_buildViewControls())
        ..add(_buildNodeActionBar(state));
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: isTouchOnly,
      appBar: isTouchOnly ? _buildTouchAppBar(mapName) : null,
      floatingActionButtonLocation: isTouchOnly
          ? FloatingActionButtonLocation.endFloat
          : null,
      floatingActionButton: isTouchOnly
          ? Padding(
              padding: const EdgeInsets.only(bottom: 16, right: 16),
              child: FloatingActionButton(
                heroTag: 'touch_reset_view',
                onPressed: _viewController.resetView,
                tooltip: 'Reset view',
                child: const Icon(Icons.center_focus_strong),
              ),
            )
          : null,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.cloudWhite, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(children: stackChildren),
      ),
    );
  }

  PreferredSizeWidget _buildTouchAppBar(String mapName) {
    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: theme.colorScheme.surface,
      elevation: 0,
      title: Text(mapName, overflow: TextOverflow.ellipsis),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back to overview',
        onPressed: () {
          Navigator.of(context).pop();
        },
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: CloudSyncStatus(
            compact: true,
            onTap: () => showCloudSyncSheet(context),
          ),
        ),
        PopupMenuButton<_ExportAction>(
          icon: const Icon(Icons.ios_share),
          tooltip: 'Export',
          onSelected: (value) {
            switch (value) {
              case _ExportAction.markdown:
                _exportMarkdown();
                break;
              case _ExportAction.svg:
                _exportSvg();
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _ExportAction.markdown,
              child: Text('Export text'),
            ),
            PopupMenuItem(value: _ExportAction.svg, child: Text('Export SVG')),
          ],
        ),
      ],
    );
  }

  Widget _buildTopControls(String mapName) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 720;
            final header = _buildHeader(mapName, showName: !isCompact);
            final syncStatus = CloudSyncStatus(
              compact: isCompact,
              onTap: () => showCloudSyncSheet(context),
            );
            final toolbar = _buildToolbar();
            return Row(
              children: [
                header,
                const SizedBox(width: 12),
                syncStatus,
                const Spacer(),
                toolbar,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(String mapName, {required bool showName}) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(appCornerRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to overview',
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            if (showName) ...[
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  mapName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(width: 12),
            CloudSyncStatus(
              compact: true,
              onTap: () => showCloudSyncSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(appCornerRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: 'Export text',
              onPressed: _exportMarkdown,
            ),
            IconButton(
              icon: const Icon(Icons.image_outlined),
              tooltip: 'Export SVG',
              onPressed: _exportSvg,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewControls() {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _floatingActionButton(
                heroTag: 'view_zoom_in',
                icon: Icons.zoom_in,
                tooltip: 'Zoom in',
                onPressed: _viewController.zoomIn,
              ),
              const SizedBox(width: 12),
              _floatingActionButton(
                heroTag: 'view_reset',
                icon: Icons.center_focus_strong,
                tooltip: 'Reset view',
                onPressed: _viewController.resetView,
              ),
              const SizedBox(width: 12),
              _floatingActionButton(
                heroTag: 'view_zoom_out',
                icon: Icons.zoom_out,
                tooltip: 'Zoom out',
                onPressed: _viewController.zoomOut,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodeActionBar(MindMapState state) {
    final selectedId = state.selectedNodeId;
    if (selectedId == null) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(mindMapProvider.notifier);
    final theme = Theme.of(context);
    final canDelete = state.root.id != selectedId;

    return SafeArea(
      top: false,
      bottom: false,
      left: false,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _floatingActionButton(
                heroTag: 'node_add_child',
                icon: Icons.subdirectory_arrow_right,
                tooltip: 'Add child',
                onPressed: () {
                  final newId = notifier.addChild(selectedId);
                  if (newId != null) {
                    _viewController.focusOnNode(newId);
                  }
                },
              ),
              const SizedBox(height: 12),
              _floatingActionButton(
                heroTag: 'node_add_sibling',
                icon: Icons.account_tree_outlined,
                tooltip: 'Add sibling',
                onPressed: () {
                  final newId = notifier.addSibling(selectedId);
                  if (newId != null) {
                    _viewController.focusOnNode(newId);
                  }
                },
              ),
              const SizedBox(height: 12),
              _floatingActionButton(
                heroTag: 'node_delete',
                icon: Icons.delete_outline,
                tooltip: 'Delete node',
                onPressed: canDelete
                    ? () => notifier.removeNode(selectedId)
                    : null,
                backgroundColor: canDelete ? theme.colorScheme.error : null,
                foregroundColor: canDelete ? theme.colorScheme.onError : null,
              ),
              const SizedBox(height: 12),
              _floatingActionButton(
                heroTag: 'node_edit_details',
                icon: Icons.article_outlined,
                tooltip: 'Edit details',
                onPressed: () => _editNodeDetails(selectedId),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _floatingActionButton({
    required String heroTag,
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    return FloatingActionButton.small(
      heroTag: heroTag,
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      tooltip: tooltip,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(appCornerRadius),
      ),
      elevation: 0,
      child: Icon(icon),
    );
  }

  Widget _buildBirdViewOverlay(bool isTouchOnly) {
    if (!_shouldShowBirdView(context, isTouchOnly)) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      left: false,
      top: false,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20, right: 16),
          child: MindMapBirdView(controller: _viewController),
        ),
      ),
    );
  }

  bool _shouldShowBirdView(BuildContext context, bool isTouchOnly) {
    if (isTouchOnly) {
      return false;
    }
    final size = MediaQuery.sizeOf(context);
    return size.shortestSide >= birdViewMinShortestSide;
  }

  Future<Uint8List?> _generateBirdViewPreview(MindMapState state) async {
    if (!mounted) {
      return null;
    }
    final layout = MindMapLayoutEngine(
      textStyle: textStyle,
      textScaler: MediaQuery.textScalerOf(context),
    ).layout(state.root);
    return BirdViewRenderer.renderPreview(layout: layout);
  }
}

enum _ExportAction { markdown, svg }
