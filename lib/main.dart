import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'src/screens/map_overview_page.dart';
import 'src/state/mind_map_storage.dart';
import 'src/state/mind_map_preview_storage.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final box = await Hive.openBox<String>('maps');
  final previewBox = await Hive.openBox<Uint8List>('map_previews');
  runApp(
    ProviderScope(
      overrides: [
        mindMapStorageProvider.overrideWithValue(MindMapStorage(box)),
        mindMapPreviewStorageProvider.overrideWithValue(
          MindMapPreviewStorage(previewBox),
        ),
      ],
      child: const MindMapApp(),
    ),
  );
}

class MindMapApp extends StatelessWidget {
  const MindMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindKite',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const MindMapOverviewPage(),
    );
  }
}
