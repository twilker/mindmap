import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../utils/json_converter.dart';
import 'mind_map_preview_storage.dart';

final mindMapStorageProvider = Provider<MindMapStorage>((ref) {
  throw UnimplementedError('MindMapStorage must be provided at runtime');
});

class MindMapStorage {
  MindMapStorage(this._box);

  final Box<String> _box;
  final MindMapJsonConverter _converter = const MindMapJsonConverter();

  List<String> listMapNames() {
    final keys = <String>[];
    final invalid = <String>[];
    for (final rawKey in _box.keys) {
      if (rawKey is! String) {
        continue;
      }
      final value = _box.get(rawKey);
      if (value == null || _converter.fromJson(value) == null) {
        invalid.add(rawKey);
        continue;
      }
      keys.add(rawKey);
    }
    for (final key in invalid) {
      unawaited(_box.delete(key));
    }
    keys.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return keys;
  }

  Future<void> saveMap(String name, String document) =>
      _box.put(name, document);

  Future<String?> loadMap(String name) async {
    final value = _box.get(name);
    if (value == null) {
      return null;
    }
    if (_converter.fromJson(value) == null) {
      unawaited(_box.delete(name));
      return null;
    }
    return value;
  }

  Future<void> deleteMap(String name) => _box.delete(name);
}

class SavedMapsNotifier extends StateNotifier<List<String>> {
  SavedMapsNotifier(this._storage, this._previewStorage)
    : super(_storage.listMapNames());

  final MindMapStorage _storage;
  final MindMapPreviewStorage _previewStorage;

  Future<void> refresh() async {
    state = _storage.listMapNames();
  }

  Future<void> save(
    String name,
    String document, {
    bool silent = false,
    Uint8List? preview,
  }) async {
    await _storage.saveMap(name, document);
    if (preview != null) {
      await _previewStorage.savePreview(name, preview);
    } else {
      await _previewStorage.deletePreview(name);
    }
    if (silent) {
      return;
    }
    await refresh();
  }

  Future<void> delete(String name) async {
    await _storage.deleteMap(name);
    await _previewStorage.deletePreview(name);
    await refresh();
  }

  Future<String?> load(String name) => _storage.loadMap(name);
}

final savedMapsProvider =
    StateNotifierProvider<SavedMapsNotifier, List<String>>((ref) {
      final storage = ref.watch(mindMapStorageProvider);
      final previewStorage = ref.watch(mindMapPreviewStorageProvider);
      return SavedMapsNotifier(storage, previewStorage);
    });
