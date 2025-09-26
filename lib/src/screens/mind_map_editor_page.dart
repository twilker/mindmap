import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_html/html.dart' as html;

import '../layout/mind_map_layout.dart';
import '../state/current_map.dart';
import '../state/mind_map_state.dart';
import '../state/mind_map_storage.dart';
import '../state/node_edit_request.dart';
import '../utils/constants.dart';
import '../utils/svg_exporter.dart';
import '../widgets/mind_map_view.dart';

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
  String? _lastSavedMarkdown;
  String? _pendingMarkdown;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentMapName = widget.mapName;
    ref.read(currentMapNameProvider.notifier).state = widget.mapName;
    _lastSavedMarkdown = ref.read(mindMapProvider).markdown;
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
    if (next.markdown == _lastSavedMarkdown ||
        next.markdown == _pendingMarkdown) {
      return;
    }
    _pendingMarkdown = next.markdown;
    if (_saving) {
      return;
    }
    _saving = true;
    unawaited(_runSaveLoop());
  }

  Future<void> _runSaveLoop() async {
    while (_pendingMarkdown != null) {
      final name = _currentMapName;
      if (name == null) {
        break;
      }
      final pending = _pendingMarkdown!;
      _pendingMarkdown = null;
      try {
        await ref
            .read(savedMapsProvider.notifier)
            .save(name, pending, silent: true);
        _lastSavedMarkdown = pending;
      } catch (err) {
        if (mounted) {
          _showMessage('Failed to save "$name": $err');
        }
        _pendingMarkdown ??= pending;
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

  void _exportMarkdown() {
    final markdown = ref.read(mindMapProvider.notifier).exportMarkdown();
    _downloadText('mindmap.txt', markdown, 'text/plain');
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
    _downloadText('mindmap.svg', svg, 'image/svg+xml');
  }

  void _downloadText(String filename, String content, String mimeType) {
    if (!kIsWeb) {
      _showMessage('File export is supported on the web build of this sample.');
      return;
    }
    final bytes = utf8.encode(content);
    final blob = html.Blob([Uint8List.fromList(bytes)], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mindMapProvider);
    _lastSavedMarkdown ??= state.markdown;
    final mapName = ref.watch(currentMapNameProvider) ?? widget.mapName;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: MindMapView(controller: _viewController)),
          _buildTopControls(mapName),
          _buildViewControls(),
          _buildNodeActionBar(state),
        ],
      ),
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
            final toolbar = _buildToolbar();
            return Row(children: [header, const Spacer(), toolbar]);
          },
        ),
      ),
    );
  }

  Widget _buildHeader(String mapName, {required bool showName}) {
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
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
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  mapName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
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
              icon: const Icon(Icons.image),
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
    final editRequest = ref.read(nodeEditRequestProvider.notifier);

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
                heroTag: 'node_edit',
                icon: Icons.edit_outlined,
                tooltip: 'Edit node',
                onPressed: () {
                  notifier.selectNode(selectedId);
                  editRequest.state = null;
                  editRequest.state = selectedId;
                  _viewController.focusOnNode(
                    selectedId,
                    preferTopHalf: _isTouchOnlyPlatform(),
                  );
                },
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
      child: Icon(icon),
    );
  }

  bool _isTouchOnlyPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        return true;
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return false;
    }
  }
}
