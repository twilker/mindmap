import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'src/state/mind_map_storage.dart';
import 'src/widgets/controls_panel.dart';
import 'src/widgets/mind_map_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final box = await Hive.openBox<String>('maps');
  runApp(
    ProviderScope(
      overrides: [mindMapStorageProvider.overrideWithValue(MindMapStorage(box))],
      child: const MindMapApp(),
    ),
  );
}

class MindMapApp extends StatelessWidget {
  const MindMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mind Map Editor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        useMaterial3: true,
      ),
      home: const MindMapHomePage(),
    );
  }
}

class MindMapHomePage extends ConsumerWidget {
  const MindMapHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = MediaQuery.of(context);
    final isNarrow = layout.size.width < 960;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isNarrow ? _buildVerticalLayout() : _buildHorizontalLayout(),
        ),
      ),
    );
  }

  Widget _buildVerticalLayout() {
    return Column(
      children: const [
        SizedBox(height: 320, child: Card(margin: EdgeInsets.zero, child: Padding(padding: EdgeInsets.all(16), child: ControlsPanel()))),
        SizedBox(height: 16),
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: MindMapView(),
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalLayout() {
    return Row(
      children: const [
        SizedBox(
          width: 320,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: ControlsPanel(),
            ),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: MindMapView(),
          ),
        ),
      ],
    );
  }
}
