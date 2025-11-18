import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final mindMapPreviewStorageProvider = Provider<MindMapPreviewStorage>((ref) {
  return MindMapPreviewStorage._noop();
});

class MindMapPreviewStorage {
  MindMapPreviewStorage(this._box);

  MindMapPreviewStorage._noop() : _box = null;

  final Box<Uint8List>? _box;

  Future<Uint8List?> loadPreview(String name) async => _box?.get(name);

  Future<void> savePreview(String name, Uint8List data) async {
    await _box?.put(name, data);
  }

  Future<void> deletePreview(String name) async {
    await _box?.delete(name);
  }

  Future<void> renamePreview(String oldName, String newName) async {
    final data = await loadPreview(oldName);
    if (data != null) {
      await savePreview(newName, data);
    }
    await deletePreview(oldName);
  }
}

final mindMapPreviewProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  name,
) async {
  final storage = ref.watch(mindMapPreviewStorageProvider);
  return storage.loadPreview(name);
});
