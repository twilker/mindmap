import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_html/html.dart' as html;

import '../layout/mind_map_layout.dart';
import '../state/mind_map_state.dart';
import '../state/mind_map_storage.dart';
import '../utils/constants.dart';
import '../utils/mindmeister_importer.dart';
import '../utils/svg_exporter.dart';

class ControlsPanel extends ConsumerStatefulWidget {
  const ControlsPanel({super.key});

  @override
  ConsumerState<ControlsPanel> createState() => _ControlsPanelState();
}

class _ControlsPanelState extends ConsumerState<ControlsPanel> {
  final TextEditingController _nameController = TextEditingController();
  String? _selectedMap;
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _importMarkdown() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      return;
    }
    final content = utf8.decode(bytes);
    ref.read(mindMapProvider.notifier).importFromMarkdown(content);
  }

  Future<void> _importMindFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mind'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final markdown = await MindmeisterImporter().toMarkdown(bytes);
      ref.read(mindMapProvider.notifier).importFromMarkdown(markdown);
    } catch (err) {
      if (mounted) {
        _showMessage('Failed to import .mind file: $err');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _exportMarkdown() {
    final markdown = ref.read(mindMapProvider.notifier).exportMarkdown();
    _downloadText('mindmap.txt', markdown, 'text/plain');
  }

  void _exportSvg() {
    final state = ref.read(mindMapProvider);
    final layout = MindMapLayoutEngine(textStyle: textStyle).layout(state.root);
    final exporter = SvgExporter(layout: layout, bounds: state.lastContentBounds ?? layout.bounds);
    final svg = exporter.build();
    _downloadText('mindmap.svg', svg, 'image/svg+xml');
  }

  Future<void> _saveMap() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Enter a name before saving.');
      return;
    }
    final markdown = ref.read(mindMapProvider.notifier).exportMarkdown();
    final storage = ref.read(savedMapsProvider.notifier);
    await storage.save(name, markdown);
    setState(() => _selectedMap = name);
    _showMessage('Saved "$name"');
  }

  Future<void> _loadSelected() async {
    final selected = _selectedMap;
    if (selected == null) {
      _showMessage('Choose a map to load.');
      return;
    }
    final storage = ref.read(savedMapsProvider.notifier);
    final content = await storage.load(selected);
    if (content == null) {
      _showMessage('Map "$selected" not found.');
      return;
    }
    ref.read(mindMapProvider.notifier).importFromMarkdown(content);
    _showMessage('Loaded "$selected"');
  }

  Future<void> _deleteSelected() async {
    final selected = _selectedMap;
    if (selected == null) {
      _showMessage('Select a map to delete.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete mind map'),
        content: Text('Delete "$selected"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final storage = ref.read(savedMapsProvider.notifier);
    await storage.delete(selected);
    if (mounted) {
      setState(() {
        _selectedMap = null;
        if (_nameController.text.trim() == selected) {
          _nameController.clear();
        }
      });
      _showMessage('Deleted "$selected"');
    }
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final savedMaps = ref.watch(savedMapsProvider);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mind Map Editor',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('Click a node to edit, press Enter for a sibling, Tab for a child.'),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.file_open),
                label: const Text('Import text'),
                onPressed: _busy ? null : _importMarkdown,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Import .mind'),
                onPressed: _busy ? null : _importMindFile,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_alt),
                label: const Text('Export text'),
                onPressed: _exportMarkdown,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.image),
                label: const Text('Export SVG'),
                onPressed: _exportSvg,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('Autofit view'),
                onPressed: () => ref.read(mindMapProvider.notifier).requestAutoFit(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Map name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedMap,
                  decoration: const InputDecoration(labelText: 'Saved maps', border: OutlineInputBorder()),
                  items: savedMaps
                      .map(
                        (name) => DropdownMenuItem(
                          value: name,
                          child: Text(name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedMap = value);
                    if (value != null) {
                      _nameController.text = value;
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  ElevatedButton(onPressed: _saveMap, child: const Text('Save')),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _loadSelected, child: const Text('Load')),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _deleteSelected, child: const Text('Delete')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
