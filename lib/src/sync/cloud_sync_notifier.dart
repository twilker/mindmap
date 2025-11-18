import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_html/html.dart' as html;

import '../sync/cloud_connector.dart';
import '../sync/cloud_service.dart';
import '../sync/cloud_sync_operation.dart';
import '../sync/cloud_sync_queue_storage.dart';
import '../sync/cloud_sync_state.dart';
import 'secure_storage.dart';
import 'google_drive_connector.dart';

final secureStorageProvider = Provider<SecureStore>((ref) {
  throw UnimplementedError('secureStorageProvider must be overridden');
});

final cloudSyncQueueStorageProvider = Provider<CloudSyncQueueStorage>((ref) {
  throw UnimplementedError('cloudSyncQueueStorageProvider must be overridden');
});

final cloudSyncNotifierProvider =
    StateNotifierProvider<CloudSyncNotifier, CloudSyncState>((ref) {
      final queueStorage = ref.watch(cloudSyncQueueStorageProvider);
      final storage = ref.watch(secureStorageProvider);
      final connectors = <CloudConnector>[
        GoogleDriveConnector(secureStorage: storage),
      ];
      final notifier = CloudSyncNotifier(queueStorage, connectors);
      notifier.initialize();
      ref.onDispose(notifier.dispose);
      return notifier;
    });

class CloudSyncNotifier extends StateNotifier<CloudSyncState> {
  CloudSyncNotifier(this._queueStorage, List<CloudConnector> connectors)
    : _connectors = {
        for (final connector in connectors) connector.type: connector,
      },
      super(
        CloudSyncState(
          services: {
            for (final connector in connectors)
              connector.type: CloudServiceState(
                service: cloudServices[connector.type]!,
                connected: connector.state.connected,
                connecting: connector.state.connecting,
                userLabel: connector.state.userLabel,
                error: connector.state.error,
              ),
          },
          pendingOperations: 0,
          syncing: false,
        ),
      );

  final CloudSyncQueueStorage _queueStorage;
  final Map<CloudServiceType, CloudConnector> _connectors;
  final _queue = <CloudSyncOperation>[];
  bool _processing = false;
  StreamSubscription<html.Event>? _onlineSubscription;

  Future<void> initialize() async {
    _queue
      ..clear()
      ..addAll(await _queueStorage.loadQueue());
    state = state.copyWith(pendingOperations: _queue.length);
    for (final connector in _connectors.values) {
      await connector.initialize();
      _updateServiceState(connector);
    }
    _processing = false;
    _attachOnlineListener();
    unawaited(_processQueue());
  }

  Future<void> connect(CloudServiceType type) async {
    final connector = _connectors[type];
    if (connector == null) {
      return;
    }
    _updateServiceState(
      connector,
      override: connector.state.copyWith(connecting: true, error: null),
    );
    await connector.connect();
    _updateServiceState(connector);
    state = state.copyWith(
      lastError: connector.state.error,
      clearError: connector.state.error == null,
    );
    unawaited(_processQueue());
  }

  Future<void> disconnect(CloudServiceType type) async {
    final connector = _connectors[type];
    if (connector == null) {
      return;
    }
    await connector.disconnect();
    _updateServiceState(connector);
    state = state.copyWith(clearError: true);
  }

  Future<void> enqueueCreate(String name, String document) async {
    await _enqueue(
      CloudSyncOperation(
        mapName: name,
        type: CloudSyncOperationType.create,
        document: document,
      ),
    );
  }

  Future<void> enqueueUpdate(String name, String document) async {
    await _enqueue(
      CloudSyncOperation(
        mapName: name,
        type: CloudSyncOperationType.update,
        document: document,
      ),
    );
  }

  Future<void> enqueueDelete(String name) async {
    await _enqueue(
      CloudSyncOperation(
        mapName: name,
        type: CloudSyncOperationType.delete,
        document: '',
      ),
    );
  }

  Future<void> _enqueue(CloudSyncOperation operation) async {
    final existingIndex = _queue.lastIndexWhere(
      (op) => op.mapName == operation.mapName,
    );
    if (existingIndex != -1) {
      final existing = _queue[existingIndex];
      if (operation.type == CloudSyncOperationType.update &&
          (existing.type == CloudSyncOperationType.update ||
              existing.type == CloudSyncOperationType.create)) {
        _queue[existingIndex] = CloudSyncOperation(
          mapName: existing.mapName,
          type: existing.type,
          document: operation.document,
          queuedAt: existing.queuedAt,
        );
      } else if (operation.type == CloudSyncOperationType.delete &&
          existing.type == CloudSyncOperationType.create) {
        _queue.removeAt(existingIndex);
      } else {
        _queue.add(operation);
      }
    } else {
      _queue.add(operation);
    }
    await _queueStorage.saveQueue(_queue);
    state = state.copyWith(pendingOperations: _queue.length);
    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    if (_processing) {
      return;
    }
    if (_queue.isEmpty) {
      state = state.copyWith(syncing: false, lastError: null, clearError: true);
      return;
    }
    final activeConnectors = _connectors.values.where(
      (connector) => connector.state.connected,
    );
    if (activeConnectors.isEmpty) {
      return;
    }
    _processing = true;
    state = state.copyWith(syncing: true, lastError: null, clearError: true);
    while (_queue.isNotEmpty) {
      final operation = _queue.first;
      var success = true;
      for (final connector in activeConnectors) {
        final handled = await connector.applyOperation(operation);
        success = success && handled;
        _updateServiceState(connector);
      }
      if (!success) {
        state = state.copyWith(
          syncing: false,
          lastError: 'Synchronization paused. Will retry when connected.',
        );
        break;
      }
      _queue.removeAt(0);
      await _queueStorage.saveQueue(_queue);
      state = state.copyWith(
        pendingOperations: _queue.length,
        lastSyncedAt: DateTime.now(),
        lastError: null,
        clearError: true,
      );
    }
    _processing = false;
    state = state.copyWith(syncing: false);
  }

  void _updateServiceState(
    CloudConnector connector, {
    CloudServiceState? override,
  }) {
    final current = override ?? connector.state;
    state = state.copyWith(
      services: {...state.services, connector.type: current},
    );
  }

  void _attachOnlineListener() {
    if (!kIsWeb) {
      return;
    }
    _onlineSubscription?.cancel();
    _onlineSubscription = html.window.onOnline.listen((_) {
      unawaited(_processQueue());
    });
  }

  @override
  void dispose() {
    for (final connector in _connectors.values) {
      connector.dispose();
    }
    _onlineSubscription?.cancel();
    super.dispose();
  }
}
