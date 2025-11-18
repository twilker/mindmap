import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:mindmap_app/main.dart';
import 'package:mindmap_app/src/state/mind_map_storage.dart';
import 'package:mindmap_app/src/state/mind_map_preview_storage.dart';
import 'package:mindmap_app/src/sync/cloud_sync_notifier.dart';
import 'package:mindmap_app/src/sync/cloud_sync_queue_storage.dart';
import 'package:mindmap_app/src/sync/cloud_sync_state.dart';
import 'package:mindmap_app/src/sync/secure_storage.dart';

void main() {
  late Directory tempDir;
  late Box<String> box;
  late Box<Uint8List> previewBox;
  late Box<String> syncQueueBox;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('mindmap_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('maps');
    previewBox = await Hive.openBox<Uint8List>('map_previews');
    syncQueueBox = await Hive.openBox<String>('cloud_sync_queue');
  });

  tearDownAll(() async {
    await box.close();
    await previewBox.close();
    await syncQueueBox.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('shows mind map overview header', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mindMapStorageProvider.overrideWithValue(MindMapStorage(box)),
          mindMapPreviewStorageProvider.overrideWithValue(
            MindMapPreviewStorage(previewBox),
          ),
          cloudSyncQueueStorageProvider.overrideWithValue(
            CloudSyncQueueStorage(syncQueueBox),
          ),
          secureStorageProvider.overrideWithValue(_FakeSecureStorage()),
          cloudSyncNotifierProvider.overrideWith(
            (ref) => CloudSyncNotifier(
              ref.read(cloudSyncQueueStorageProvider),
              const [],
            ),
          ),
        ],
        child: const MindMapApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.text('MindKite'), findsOneWidget);
    expect(find.text('Let ideas fly freely.'), findsOneWidget);
  });
}

class _FakeSecureStorage implements SecureStore {
  final Map<String, String> _storage = {};

  @override
  Future<bool> containsKey(String key) async => _storage.containsKey(key);

  @override
  Future<void> delete(String key) async => _storage.remove(key);

  @override
  Future<void> deleteAll() async => _storage.clear();

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.from(_storage);

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      _storage.remove(key);
    } else {
      _storage[key] = value;
    }
  }
}
