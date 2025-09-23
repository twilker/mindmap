import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

final mindMapStorageProvider = Provider<MindMapStorage>((ref) {
  throw UnimplementedError('MindMapStorage must be provided at runtime');
});

class MindMapStorage {
  MindMapStorage(this._box);

  final Box<String> _box;

  List<String> listMapNames() {
    final keys = _box.keys.cast<String>().toList();
    keys.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return keys;
  }

  Future<void> saveMap(String name, String markdown) =>
      _box.put(name, markdown);

  Future<String?> loadMap(String name) async => _box.get(name);

  Future<void> deleteMap(String name) => _box.delete(name);
}

class SavedMapsNotifier extends StateNotifier<List<String>> {
  SavedMapsNotifier(this._storage) : super(_storage.listMapNames());

  final MindMapStorage _storage;

  Future<void> refresh() async {
    state = _storage.listMapNames();
  }

  Future<void> save(String name, String markdown, {bool silent = false}) async {
    await _storage.saveMap(name, markdown);
    if (silent) {
      return;
    }
    await refresh();
  }

  Future<void> delete(String name) async {
    await _storage.deleteMap(name);
    await refresh();
  }

  Future<String?> load(String name) => _storage.loadMap(name);
}

final savedMapsProvider =
    StateNotifierProvider<SavedMapsNotifier, List<String>>((ref) {
      final storage = ref.watch(mindMapStorageProvider);
      return SavedMapsNotifier(storage);
    });
