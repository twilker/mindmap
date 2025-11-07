import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'cloud_sync_models.dart';

class CloudSyncPersistence {
  CloudSyncPersistence(this._box);

  static const _queueKey = 'queue';
  static const _accountsKey = 'accounts';

  final Box<String> _box;

  List<SyncQueueEntry> loadQueue() {
    final raw = _box.get(_queueKey);
    if (raw == null) {
      return const [];
    }
    try {
      final data = jsonDecode(raw) as List;
      return [
        for (final item in data)
          if (item is Map<String, dynamic>) SyncQueueEntry.fromJson(item)
          else if (item is Map)
            SyncQueueEntry.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveQueue(List<SyncQueueEntry> queue) {
    final encoded = jsonEncode(queue.map((e) => e.toJson()).toList());
    return _box.put(_queueKey, encoded);
  }

  Map<String, CloudAccountData> loadAccounts() {
    final raw = _box.get(_accountsKey);
    if (raw == null) {
      return const {};
    }
    try {
      final data = jsonDecode(raw) as Map;
      return data.map((key, value) {
        final map = (value as Map).cast<String, dynamic>();
        return MapEntry(
          key.toString(),
          CloudAccountData.fromJson(map),
        );
      });
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveAccounts(Map<String, CloudAccountData> accounts) {
    final encoded = jsonEncode(
      accounts.map((key, value) => MapEntry(key, value.toJson())),
    );
    return _box.put(_accountsKey, encoded);
  }

  Future<void> clear() => _box.clear();
}
