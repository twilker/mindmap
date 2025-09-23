import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: MindMapView()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topLeft,
                child: _buildHeader(mapName),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topRight,
                child: _buildToolbar(),
              ),
            ),
          ),
        ],
      ),
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

  Widget _buildToolbar() {
    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
    );
  }
}
