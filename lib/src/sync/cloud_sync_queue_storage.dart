import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'cloud_sync_operation.dart';

class CloudSyncQueueStorage {
  CloudSyncQueueStorage(this._box);

  static const _queueKey = 'queue';

  final Box<String> _box;

  Future<List<CloudSyncOperation>> loadQueue() async {
    final raw = _box.get(_queueKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => CloudSyncOperation.fromJson(jsonEncode(e)))
        .toList();
  }

  Future<void> saveQueue(List<CloudSyncOperation> queue) async {
    final encoded = jsonEncode(queue.map((e) => e.toJson()).toList());
    await _box.put(_queueKey, encoded);
  }
}
