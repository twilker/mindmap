import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../state/current_map.dart';
import '../state/mind_map_state.dart';
import '../state/mind_map_storage.dart';
import '../utils/markdown_converter.dart';
import '../utils/mindmeister_importer.dart';
import 'mind_map_editor_page.dart';

class MindMapOverviewPage extends ConsumerStatefulWidget {
  const MindMapOverviewPage({super.key});

  @override
  ConsumerState<MindMapOverviewPage> createState() =>
      _MindMapOverviewPageState();
}

class _MindMapOverviewPageState extends ConsumerState<MindMapOverviewPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final savedMaps = ref.watch(savedMapsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your mind maps'), centerTitle: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_circle),
                    label: const Text('New mind map'),
                    onPressed: _busy ? null : _createNewMap,
                  ),
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
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: savedMaps.isEmpty
                    ? _buildEmptyState()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final columnWidth = 260.0;
                          final count = (constraints.maxWidth / columnWidth)
                              .floor()
                              .clamp(1, 4);
                          return GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: count,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: 1.25,
                                ),
                            itemCount: savedMaps.length,
                            itemBuilder: (context, index) {
                              final name = savedMaps[index];
                              return _MindMapCard(
                                name: name,
                                onOpen: () => _openMap(name),
                                onDelete: () => _confirmDelete(name),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.account_tree_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No mind maps yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Text('Create a new map or import one to get started.'),
        ],
      ),
    );
  }

  Future<void> _createNewMap() async {
    final existing = ref.read(savedMapsProvider);
    final suggested = _suggestName('Untitled map', existing);
    final name = await _promptForName(
      title: 'Create new mind map',
      initialValue: suggested,
      existingNames: existing,
    );
    if (name == null) {
      return;
    }

    final tempNotifier = MindMapNotifier();
    final markdown = tempNotifier.exportMarkdown();
    tempNotifier.dispose();
    await ref.read(savedMapsProvider.notifier).save(name, markdown);
    await _openMap(name, preloadedMarkdown: markdown);
    _showMessage('Created "$name"');
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
      _showMessage('Unable to read ${file.name}.');
      return;
    }
    final content = utf8.decode(bytes);
    final converter = MindMapMarkdownConverter(const Uuid().v4);
    final root = converter.fromMarkdown(content);
    if (root == null) {
      _showMessage('The selected file could not be parsed as a mind map.');
      return;
    }
    final normalized = converter.toMarkdown(root);
    await _createMapFromMarkdown(
      normalized,
      suggestedName: _suggestName(
        _nameWithoutExtension(file.name),
        ref.read(savedMapsProvider),
      ),
    );
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
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _showMessage('Unable to read ${file.name}.');
      return;
    }
    setState(() => _busy = true);
    try {
      final markdown = await MindmeisterImporter().toMarkdown(bytes);
      await _createMapFromMarkdown(
        markdown,
        suggestedName: _suggestName(
          _nameWithoutExtension(file.name),
          ref.read(savedMapsProvider),
        ),
      );
    } catch (err) {
      _showMessage('Failed to import .mind file: $err');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _createMapFromMarkdown(
    String markdown, {
    required String suggestedName,
  }) async {
    final existing = ref.read(savedMapsProvider);
    final name = await _promptForName(
      title: 'Name imported map',
      initialValue: suggestedName,
      existingNames: existing,
    );
    if (name == null) {
      return;
    }
    final converter = MindMapMarkdownConverter(const Uuid().v4);
    final root = converter.fromMarkdown(markdown);
    if (root == null) {
      _showMessage('Unable to process the imported map.');
      return;
    }
    final normalized = converter.toMarkdown(root);
    await ref.read(savedMapsProvider.notifier).save(name, normalized);
    await _openMap(name, preloadedMarkdown: normalized);
    _showMessage('Imported "$name"');
  }

  Future<void> _openMap(String name, {String? preloadedMarkdown}) async {
    final storage = ref.read(savedMapsProvider.notifier);
    var markdown = preloadedMarkdown;
    markdown ??= await storage.load(name);
    if (markdown == null) {
      _showMessage('Map "$name" was not found.');
      return;
    }
    ref.read(mindMapProvider.notifier).importFromMarkdown(markdown);
    ref.read(currentMapNameProvider.notifier).state = name;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MindMapEditorPage(mapName: name)));
    ref.read(currentMapNameProvider.notifier).state = null;
  }

  Future<void> _confirmDelete(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete mind map'),
        content: Text('Delete "$name"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(savedMapsProvider.notifier).delete(name);
    _showMessage('Deleted "$name"');
  }

  Future<String?> _promptForName({
    required String title,
    String? initialValue,
    required List<String> existingNames,
  }) async {
    final controller = TextEditingController(text: initialValue);
    String? error;
    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Mind map name',
                  errorText: error,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.isEmpty) {
                      setState(() => error = 'Enter a name.');
                      return;
                    }
                    if (existingNames.contains(value)) {
                      setState(
                        () => error = 'A map with this name already exists.',
                      );
                      return;
                    }
                    Navigator.of(context).pop(value);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _suggestName(String base, List<String> existing) {
    if (!existing.contains(base)) {
      return base;
    }
    var index = 2;
    while (existing.contains('$base $index')) {
      index++;
    }
    return '$base $index';
  }

  String _nameWithoutExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) {
      return name;
    }
    return name.substring(0, dot);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MindMapCard extends StatelessWidget {
  const _MindMapCard({
    required this.name,
    required this.onOpen,
    required this.onDelete,
  });

  final String name;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      Icons.account_tree,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete mind map',
                    onPressed: onDelete,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                'Tap to open',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
