import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:uuid/uuid.dart';

import '../layout/mind_map_layout.dart';
import '../state/current_map.dart';
import '../state/mind_map_state.dart';
import '../state/mind_map_storage.dart';
import '../state/mind_map_preview_storage.dart';
import '../theme/app_colors.dart';
import '../utils/constants.dart';
import '../utils/markdown_converter.dart';
import '../utils/mindmeister_importer.dart';
import '../utils/bird_view_renderer.dart';
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
    final theme = Theme.of(context);
    final savedMaps = ref.watch(savedMapsProvider);

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.cloudWhite, Colors.white],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroSection(theme),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.flight_takeoff_rounded),
                        label: const Text('New mind map'),
                        onPressed: _busy ? null : _createNewMap,
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.file_open),
                        label: const Text('Import text'),
                        onPressed: _busy ? null : _importMarkdown,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Import .mind'),
                        onPressed: _busy ? null : _importMindFile,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      child: savedMaps.isEmpty
                          ? _buildEmptyState(theme)
                          : _buildSavedMapsGrid(savedMaps),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_busy) const _BusyOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeroSection(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(
            gradient: AppColors.heroGradient,
            color: Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(appCornerRadius),
          ),
          child: SvgPicture.asset(
            'assets/logo/mindkite_mark_notail_light.svg',
            height: 128,
            width: 128,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'MindKite',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Let ideas fly freely.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onBackground.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(appCornerRadius),
          border: Border.all(color: AppColors.graphSlate.withOpacity(0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.12),
              ),
              child: Icon(
                Icons.airplanemode_active,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No mind maps yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Create a new map or import one to get started.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onBackground.withOpacity(0.65),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedMapsGrid(List<String> savedMaps) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columnWidth = 260.0;
        final count = (constraints.maxWidth / columnWidth).floor().clamp(1, 4);
        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
            childAspectRatio: 1.2,
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
    final layout = MindMapLayoutEngine(
      textStyle: textStyle,
      textScaler: MediaQuery.textScalerOf(context),
    ).layout(tempNotifier.state.root);
    final preview = await BirdViewRenderer.renderPreview(layout: layout);
    final markdown = tempNotifier.exportMarkdown();
    tempNotifier.dispose();
    await ref
        .read(savedMapsProvider.notifier)
        .save(name, markdown, preview: preview);
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
    final layout = MindMapLayoutEngine(
      textStyle: textStyle,
      textScaler: MediaQuery.textScalerOf(context),
    ).layout(root);
    final preview = await BirdViewRenderer.renderPreview(layout: layout);
    await ref
        .read(savedMapsProvider.notifier)
        .save(name, normalized, preview: preview);
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
    if (!mounted) {
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

class _MindMapCard extends ConsumerWidget {
  const _MindMapCard({
    required this.name,
    required this.onOpen,
    required this.onDelete,
  });

  final String name;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final previewAsync = ref.watch(mindMapPreviewProvider(name));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(appCornerRadius),
        splashColor: colorScheme.primary.withOpacity(0.08),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(appCornerRadius),
            border: Border.all(color: colorScheme.primary.withOpacity(0.12)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(appCornerRadius - 2),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.06),
                      ),
                      child: SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 4,
                            height: 3,
                            child: _MindMapPreviewContent(
                              preview: previewAsync,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        Icons.airplanemode_on,
                        color: colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete mind map',
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap to open',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onBackground.withOpacity(0.6),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MindMapPreviewContent extends StatelessWidget {
  const _MindMapPreviewContent({required this.preview});

  final AsyncValue<Uint8List?> preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color baseColor = theme.colorScheme.onSurface.withOpacity(0.6);
    return preview.when(
      data: (data) {
        if (data == null || data.isEmpty) {
          return _PreviewPlaceholder(color: baseColor);
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            return Center(
              child: Image.memory(
                data,
                width: size.width.isFinite ? size.width : null,
                height: size.height.isFinite ? size.height : null,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            );
          },
        );
      },
      loading: () => const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => _PreviewPlaceholder(color: baseColor),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(Icons.travel_explore_outlined, color: color, size: 32),
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: AbsorbPointer(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: colorScheme.background.withOpacity(0.65),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 64, child: LinearProgressIndicator()),
                  const SizedBox(height: 16),
                  Text(
                    'Importing…',
                    style: Theme.of(context).textTheme.bodyMedium,
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
