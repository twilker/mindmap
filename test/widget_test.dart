import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:mindmap_app/main.dart';
import 'package:mindmap_app/src/state/mind_map_storage.dart';

void main() {
  late Directory tempDir;
  late Box<String> box;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('mindmap_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('maps');
  });

  tearDownAll(() async {
    await box.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('renders mind map header', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mindMapStorageProvider.overrideWithValue(MindMapStorage(box))],
        child: const MindMapApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Mind Map Editor'), findsWidgets);
  });
}
