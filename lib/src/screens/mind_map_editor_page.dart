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
    _mapNameSubscription = ref.listenManual<String?>(
      currentMapNameProvider,
      (previous, next) {
        _currentMapName = next;
      },
    );
    _mindMapSubscription = ref.listenManual<MindMapState>(
      mindMapProvider,
      (previous, next) {
        _scheduleSave(next);
      },
    );
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MindMapView(controller: _viewController),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 720;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTopBar(mapName, isCompact),
                      const Spacer(),
                      _buildActionBar(state, isCompact, keyboardInset),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(String mapName, bool isCompact) {
    final header = _buildHeader(mapName);
    final toolbar = _buildToolbar(isCompact);
    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: toolbar,
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: header),
        const SizedBox(width: 12),
        toolbar,
      ],
    );
  }

  Widget _buildHeader(String mapName) {
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
            const SizedBox(width: 8),
            Flexible(
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
        ),
      ),
    );
  }

  Widget _buildToolbar(bool isCompact) {
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
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

  Widget _buildActionBar(
    MindMapState state,
    bool isCompact,
    double keyboardInset,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedId = state.selectedNodeId;
    final notifier = ref.read(mindMapProvider.notifier);
    final buttonPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 12 : 16,
      vertical: 12,
    );
    final minPrimarySize = Size(isCompact ? 130 : 150, 48);

    VoidCallback? addChild;
    VoidCallback? addSibling;
    VoidCallback? removeNode;
    if (selectedId != null) {
      addChild = () {
        notifier.addChild(selectedId);
        notifier.requestAutoFit();
      };
      addSibling = () {
        notifier.addSibling(selectedId);
        notifier.requestAutoFit();
      };
      if (state.root.id != selectedId) {
        removeNode = () => notifier.removeNode(selectedId);
      }
    }

    final primaryActions = [
      FilledButton.icon(
        onPressed: addChild,
        style: FilledButton.styleFrom(
          padding: buttonPadding,
          minimumSize: minPrimarySize,
        ),
        icon: const Icon(Icons.subdirectory_arrow_right),
        label: const Text('Add child'),
      ),
      FilledButton.tonalIcon(
        onPressed: addSibling,
        style: FilledButton.styleFrom(
          padding: buttonPadding,
          minimumSize: minPrimarySize,
        ),
        icon: const Icon(Icons.account_tree_outlined),
        label: const Text('Add sibling'),
      ),
      FilledButton.icon(
        onPressed: removeNode,
        style: FilledButton.styleFrom(
          padding: buttonPadding,
          minimumSize: minPrimarySize,
          backgroundColor: colorScheme.error,
          foregroundColor: colorScheme.onError,
          disabledBackgroundColor: colorScheme.error.withValues(alpha: 0.12),
          disabledForegroundColor: colorScheme.onSurfaceVariant,
        ),
        icon: const Icon(Icons.delete_outline),
        label: const Text('Delete node'),
      ),
    ];

    Widget utilityButton({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
    }) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: buttonPadding,
          minimumSize: Size(isCompact ? 120 : 140, 44),
        ),
      );
    }

    final utilityActions = [
      utilityButton(
        icon: Icons.remove,
        label: 'Zoom out',
        onPressed: () => _viewController.zoomOut(),
      ),
      utilityButton(
        icon: Icons.aspect_ratio,
        label: 'Auto-fit',
        onPressed: () => notifier.requestAutoFit(),
      ),
      utilityButton(
        icon: Icons.home,
        label: 'Reset view',
        onPressed: () => _viewController.resetView(),
      ),
      utilityButton(
        icon: Icons.add,
        label: 'Zoom in',
        onPressed: () => _viewController.zoomIn(),
      ),
    ];

    final bottomPadding = keyboardInset > 0 ? keyboardInset + 12 : 0.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Material(
            color: theme.colorScheme.surface.withValues(alpha: 0.96),
            elevation: 10,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: isCompact ? WrapAlignment.center : WrapAlignment.start,
                    children: primaryActions,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: isCompact ? WrapAlignment.center : WrapAlignment.start,
                    children: utilityActions,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
