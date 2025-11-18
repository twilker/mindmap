import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'src/screens/map_overview_page.dart';
import 'src/state/mind_map_storage.dart';
import 'src/state/mind_map_preview_storage.dart';
import 'src/theme/app_theme.dart';
import 'src/sync/cloud_sync_notifier.dart';
import 'src/sync/cloud_sync_queue_storage.dart';
import 'src/sync/secure_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final box = await Hive.openBox<String>('maps');
  final previewBox = await Hive.openBox<Uint8List>('map_previews');
  final syncQueueBox = await Hive.openBox<String>('cloud_sync_queue');
  runApp(
    ProviderScope(
      overrides: [
        mindMapStorageProvider.overrideWithValue(MindMapStorage(box)),
        mindMapPreviewStorageProvider.overrideWithValue(
          MindMapPreviewStorage(previewBox),
        ),
        cloudSyncQueueStorageProvider.overrideWithValue(
          CloudSyncQueueStorage(syncQueueBox),
        ),
        secureStorageProvider.overrideWithValue(FlutterSecureStore()),
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
