import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../state/mind_map_storage.dart';
import 'cloud_sync_models.dart';
import 'cloud_sync_persistence.dart';
import 'cloud_sync_provider.dart';

class CloudSyncController extends StateNotifier<CloudSyncState> {
  CloudSyncController({
    required this.persistence,
    required this.providers,
    required this.storage,
    required FlutterSecureStorage secureStorage,
    http.Client Function()? httpClientFactory,
    Connectivity? connectivity,
  })  : _secureStorage = secureStorage,
        _httpClientFactory = httpClientFactory ?? http.Client.new,
        _connectivity = connectivity ?? Connectivity(),
        _uuid = const Uuid(),
        super(CloudSyncState.initial()) {
    _initialize();
  }

  final CloudSyncPersistence persistence;
  final Map<String, CloudSyncProvider> providers;
  final MindMapStorage storage;
  final FlutterSecureStorage _secureStorage;
  final http.Client Function() _httpClientFactory;
  final Connectivity _connectivity;
  final Uuid _uuid;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isProcessing = false;
  bool _isOnline = true;
  bool _initialized = false;

  CloudProviderContext get _context => CloudProviderContext(
        secureStorage: _secureStorage,
        httpClientFactory: _httpClientFactory,
      );

  Future<void> _initialize() async {
    final restoredAccounts = <String, CloudAccountState>{};
    final storedAccounts = persistence.loadAccounts();
    final storedQueue = persistence.loadQueue();

    for (final entry in storedAccounts.entries) {
      final provider = providers[entry.key];
      final accountData = entry.value;
      if (provider == null) {
        continue;
      }
      try {
        final restored = await provider.restore(_context, accountData);
        if (restored == null) {
          continue;
        }
        restoredAccounts[entry.key] = CloudAccountState(
          account: restored,
          stats: const SyncStats(),
        );
      } on CloudSyncException catch (err) {
        state = state.copyWith(
          activeError: err.message,
          status: err.isOffline ? CloudSyncStatus.offline : CloudSyncStatus.error,
        );
      } catch (_) {
        // Ignore and skip account restoration if it fails unexpectedly.
      }
    }

    final sanitizedQueue = <SyncQueueEntry>[];
    for (final entry in storedQueue) {
      if (restoredAccounts.isEmpty) {
        sanitizedQueue.add(entry.copyWith(pendingProviders: {}));
        continue;
      }
      final providersToKeep = entry.pendingProviders
          .where((id) => restoredAccounts.containsKey(id))
          .toSet();
      if (providersToKeep.isEmpty) {
        continue;
      }
      sanitizedQueue.add(entry.copyWith(pendingProviders: providersToKeep));
    }

    state = state.copyWith(
      accounts: restoredAccounts,
      queue: sanitizedQueue,
      status: CloudSyncStatus.idle,
      clearError: true,
    );

    await persistence.saveQueue(sanitizedQueue);

    _recomputeStats();

    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((results) {
      final online =
          results.any((result) => result != ConnectivityResult.none);
      _handleConnectivityChange(online);
    });
    final initialResults = await _connectivity.checkConnectivity();
    final initialOnline =
        initialResults.any((result) => result != ConnectivityResult.none);
    _handleConnectivityChange(initialOnline, initial: true);

    _initialized = true;
    await _processQueue();
  }

  Future<void> disposeAsync() async {
    await _connectivitySubscription?.cancel();
  }

  @override
  void dispose() {
    unawaited(disposeAsync());
    super.dispose();
  }

  Future<void> connect(String providerId) async {
    final provider = providers[providerId];
    if (provider == null) {
      return;
    }
    try {
      final account = await provider.connect(_context);
      if (account == null) {
        return;
      }
      final updatedAccounts = {
        ...state.accounts,
        providerId: CloudAccountState(
          account: account,
          stats: const SyncStats(),
        ),
      };
      state = state.copyWith(
        accounts: updatedAccounts,
        status: CloudSyncStatus.idle,
        clearError: true,
      );
      await _persistAccounts();
      final withProvider = _appendProviderToQueue(providerId);
      await persistence.saveQueue(withProvider);
      state = state.copyWith(queue: withProvider);
      _recomputeStats();
      await _enqueueFullSync(providerId);
      await _processQueue();
    } on CloudSyncException catch (err) {
      state = state.copyWith(
        status: err.isOffline ? CloudSyncStatus.offline : CloudSyncStatus.error,
        activeError: err.message,
      );
    } catch (err) {
      state = state.copyWith(
        status: CloudSyncStatus.error,
        activeError: err.toString(),
      );
    }
  }

  Future<void> disconnect(String providerId) async {
    final provider = providers[providerId];
    final accountState = state.accounts[providerId];
    if (provider != null) {
      try {
        await provider.disconnect(_context, accountState?.account);
      } catch (_) {
        // Ignore disconnect errors and continue cleanup.
      }
    }
    final updatedAccounts = {...state.accounts}..remove(providerId);
    state = state.copyWith(accounts: updatedAccounts, clearError: true);
    await _persistAccounts();

    final updatedQueue = <SyncQueueEntry>[];
    for (final entry in state.queue) {
      final remaining = {...entry.pendingProviders}..remove(providerId);
      if (remaining.isEmpty) {
        continue;
      }
      updatedQueue.add(entry.copyWith(pendingProviders: remaining));
    }
    await persistence.saveQueue(updatedQueue);
    state = state.copyWith(queue: updatedQueue);
    _recomputeStats();
  }

  Future<void> enqueueOperation(
    String mapName,
    SyncOperationType operation, {
    String? document,
    Set<String>? specificProviders,
  }) async {
    final targetProviders = specificProviders ?? state.accounts.keys.toSet();
    final queue = [...state.queue];
    final now = DateTime.now();

    if (targetProviders.isEmpty) {
      queue.add(
        SyncQueueEntry.create(
          id: _uuid.v4(),
          mapName: mapName,
          operation: operation,
          providers: {},
          timestamp: now,
          document: document,
        ),
      );
      await _updateQueue(queue, triggerProcessing: false);
      return;
    }

    final mergeIndex = queue.lastIndexWhere(
      (entry) => entry.mapName == mapName && entry.pendingProviders.isNotEmpty,
    );
    if (mergeIndex != -1) {
      final existing = queue[mergeIndex];
      final mergedProviders = {...existing.pendingProviders, ...targetProviders};
      switch (operation) {
        case SyncOperationType.update:
          if (existing.operation == SyncOperationType.update ||
              existing.operation == SyncOperationType.create) {
            queue[mergeIndex] = existing.copyWith(
              document: document ?? existing.document,
              timestamp: now,
              pendingProviders: mergedProviders,
            );
            await _updateQueue(queue);
            return;
          }
          break;
        case SyncOperationType.create:
          if (existing.operation == SyncOperationType.create) {
            queue[mergeIndex] = existing.copyWith(
              document: document ?? existing.document,
              timestamp: now,
              pendingProviders: mergedProviders,
            );
            await _updateQueue(queue);
            return;
          }
          if (existing.operation == SyncOperationType.delete) {
            queue[mergeIndex] = existing.copyWith(
              operation: SyncOperationType.update,
              document: document,
              timestamp: now,
              pendingProviders: {...targetProviders},
            );
            await _updateQueue(queue);
            return;
          }
          break;
        case SyncOperationType.delete:
          if (existing.operation == SyncOperationType.create) {
            queue.removeAt(mergeIndex);
            await _updateQueue(queue);
            return;
          }
          if (existing.operation == SyncOperationType.update ||
              existing.operation == SyncOperationType.delete) {
            queue[mergeIndex] = existing.copyWith(
              operation: SyncOperationType.delete,
              document: null,
              timestamp: now,
              pendingProviders: mergedProviders,
            );
            await _updateQueue(queue);
            return;
          }
          break;
      }
    }

    queue.add(
      SyncQueueEntry.create(
        id: _uuid.v4(),
        mapName: mapName,
        operation: operation,
        providers: targetProviders,
        timestamp: now,
        document: document,
      ),
    );
    await _updateQueue(queue);
  }

  Future<void> _enqueueFullSync(String providerId) async {
    final names = storage.listMapNames();
    for (final name in names) {
      final document = await storage.loadMap(name);
      if (document == null) {
        continue;
      }
      await enqueueOperation(
        name,
        SyncOperationType.update,
        document: document,
        specificProviders: {providerId},
      );
    }
  }

  List<SyncQueueEntry> _appendProviderToQueue(String providerId) {
    return [
      for (final entry in state.queue)
        entry.copyWith(
          pendingProviders: {...entry.pendingProviders, providerId},
        ),
    ];
  }

  Future<void> _updateQueue(
    List<SyncQueueEntry> queue, {
    bool triggerProcessing = true,
  }) async {
    state = state.copyWith(queue: queue, clearError: true);
    await persistence.saveQueue(queue);
    _recomputeStats();
    if (triggerProcessing) {
      await _processQueue();
    }
  }

  Future<void> _persistAccounts() async {
    final serialized = <String, CloudAccountData>{
      for (final entry in state.accounts.entries) entry.key: entry.value.account,
    };
    await persistence.saveAccounts(serialized);
  }

  Future<void> _processQueue() async {
    if (!_initialized || _isProcessing) {
      return;
    }
    if (!_isOnline) {
      return;
    }
    final hasPending =
        state.queue.any((entry) => entry.pendingProviders.isNotEmpty);
    if (!hasPending) {
      if (state.status != CloudSyncStatus.idle) {
        state = state.copyWith(status: CloudSyncStatus.idle, clearError: true);
      }
      return;
    }
    _isProcessing = true;
    state = state.copyWith(status: CloudSyncStatus.syncing, clearError: true);
    try {
      while (true) {
        final entry = state.queue.firstWhereOrNull(
          (item) => item.pendingProviders.isNotEmpty,
        );
        if (entry == null) {
          break;
        }
        for (final providerId in entry.pendingProviders.toList()) {
          final provider = providers[providerId];
          final accountState = state.accounts[providerId];
          if (provider == null || accountState == null) {
            await _markProviderComplete(entry.id, providerId);
            continue;
          }
          try {
            final result = await provider.performOperation(
              _context,
              accountState.account,
              entry,
            );
            _updateAccount(providerId, result);
            await _markProviderComplete(entry.id, providerId);
          } on CloudSyncException catch (err) {
            if (err.isOffline) {
              _isOnline = false;
              state = state.copyWith(
                status: CloudSyncStatus.offline,
                activeError: err.message,
              );
              await _markProviderError(entry.id, providerId, err.message);
              _isProcessing = false;
              _recomputeStats();
              return;
            }
            await _markProviderError(entry.id, providerId, err.message);
            state = state.copyWith(
              status: CloudSyncStatus.error,
              activeError: err.message,
            );
          } on SocketException catch (err) {
            _isOnline = false;
            state = state.copyWith(
              status: CloudSyncStatus.offline,
              activeError: err.message,
            );
            await _markProviderError(entry.id, providerId, err.message);
            _isProcessing = false;
            _recomputeStats();
            return;
          } catch (err) {
            await _markProviderError(entry.id, providerId, err.toString());
            state = state.copyWith(
              status: CloudSyncStatus.error,
              activeError: err.toString(),
            );
          }
        }
        await _cleanupQueue();
      }
      state = state.copyWith(status: CloudSyncStatus.idle, clearError: true);
    } finally {
      _isProcessing = false;
      _recomputeStats();
    }
  }

  Future<void> _markProviderComplete(String entryId, String providerId) async {
    final queue = [...state.queue];
    final index = queue.indexWhere((element) => element.id == entryId);
    if (index == -1) {
      return;
    }
    queue[index] = queue[index].withProviderCompleted(providerId);
    state = state.copyWith(queue: queue);
    await persistence.saveQueue(queue);
  }

  Future<void> _markProviderError(
    String entryId,
    String providerId,
    String message,
  ) async {
    final queue = [...state.queue];
    final index = queue.indexWhere((element) => element.id == entryId);
    if (index == -1) {
      return;
    }
    queue[index] = queue[index].withProviderError(providerId, message);
    state = state.copyWith(queue: queue);
    await persistence.saveQueue(queue);
    final accountState = state.accounts[providerId];
    if (accountState != null) {
      final updatedAccount = accountState.copyWith(
        stats: accountState.stats.copyWith(
          lastError: message,
          isSyncing: false,
        ),
      );
      final updatedAccounts = {
        ...state.accounts,
        providerId: updatedAccount,
      };
      state = state.copyWith(accounts: updatedAccounts);
      unawaited(_persistAccounts());
    }
  }

  Future<void> _cleanupQueue() async {
    final updated = [
      for (final entry in state.queue)
        if (!entry.isComplete) entry,
    ];
    if (updated.length != state.queue.length) {
      state = state.copyWith(queue: updated);
      await persistence.saveQueue(updated);
    }
  }

  void _updateAccount(String providerId, CloudAccountData account) {
    final accountState = state.accounts[providerId];
    if (accountState == null) {
      return;
    }
    final updatedState = accountState.copyWith(
      account: account,
      stats: accountState.stats.copyWith(
        lastSuccess: DateTime.now(),
        clearError: true,
      ),
    );
    final updatedAccounts = {
      ...state.accounts,
      providerId: updatedState,
    };
    state = state.copyWith(accounts: updatedAccounts, clearError: true);
    unawaited(_persistAccounts());
  }

  void _recomputeStats() {
    final pendingPerProvider = <String, int>{};
    for (final entry in state.queue) {
      for (final provider in entry.pendingProviders) {
        pendingPerProvider.update(provider, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    final updatedAccounts = <String, CloudAccountState>{};
    for (final entry in state.accounts.entries) {
      final pending = pendingPerProvider[entry.key] ?? 0;
      updatedAccounts[entry.key] = entry.value.copyWith(
        stats: entry.value.stats.copyWith(
          pending: pending,
          isSyncing: state.status == CloudSyncStatus.syncing,
          lastError: entry.value.stats.lastError,
        ),
      );
    }
    if (!const MapEquality().equals(updatedAccounts, state.accounts)) {
      state = state.copyWith(accounts: updatedAccounts);
    } else if (updatedAccounts.isNotEmpty) {
      state = state.copyWith(accounts: updatedAccounts);
    }
  }

  void _handleConnectivityChange(bool online, {bool initial = false}) {
    _isOnline = online;
    if (!online) {
      state = state.copyWith(status: CloudSyncStatus.offline);
      return;
    }
    if (!initial) {
      state = state.copyWith(status: CloudSyncStatus.idle, clearError: true);
    }
    if (_initialized) {
      unawaited(_processQueue());
    }
  }
}
