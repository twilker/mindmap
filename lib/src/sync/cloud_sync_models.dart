import 'dart:convert';

enum SyncOperationType { create, update, delete }

enum CloudSyncStatus { idle, syncing, offline, error }

enum CloudSyncExceptionType { offline, cancelled, authentication, unknown }

class CloudSyncException implements Exception {
  CloudSyncException._(this.type, this.message, [this.cause]);

  factory CloudSyncException.offline([String? message, Object? cause]) =>
      CloudSyncException._(
        CloudSyncExceptionType.offline,
        message ?? 'No network connection available.',
        cause,
      );

  factory CloudSyncException.cancelled([String? message]) =>
      CloudSyncException._(
        CloudSyncExceptionType.cancelled,
        message ?? 'User cancelled the request.',
      );

  factory CloudSyncException.authentication(String message, [Object? cause]) =>
      CloudSyncException._(
        CloudSyncExceptionType.authentication,
        message,
        cause,
      );

  factory CloudSyncException.unknown(String message, [Object? cause]) =>
      CloudSyncException._(
        CloudSyncExceptionType.unknown,
        message,
        cause,
      );

  final CloudSyncExceptionType type;
  final String message;
  final Object? cause;

  bool get isOffline => type == CloudSyncExceptionType.offline;

  @override
  String toString() => 'CloudSyncException($type, $message, $cause)';
}

class SyncQueueEntry {
  SyncQueueEntry({
    required this.id,
    required this.mapName,
    required this.operation,
    required this.timestamp,
    required Set<String> pendingProviders,
    Map<String, String>? errors,
    this.document,
  })  : pendingProviders = {...pendingProviders},
        errors = errors ?? {};

  factory SyncQueueEntry.create({
    required String id,
    required String mapName,
    required SyncOperationType operation,
    required Set<String> providers,
    required DateTime timestamp,
    String? document,
  }) {
    return SyncQueueEntry(
      id: id,
      mapName: mapName,
      operation: operation,
      document: document,
      timestamp: timestamp,
      pendingProviders: providers,
    );
  }

  factory SyncQueueEntry.fromJson(Map<String, dynamic> json) {
    final pending = json['pending'] as List? ?? const [];
    final errors = (json['errors'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        ) ??
        <String, String>{};
    return SyncQueueEntry(
      id: json['id'] as String,
      mapName: json['mapName'] as String,
      operation: SyncOperationType.values
          .firstWhere((e) => e.name == json['operation'] as String),
      document: json['document'] as String?,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      pendingProviders: pending.map((e) => e.toString()).toSet(),
      errors: errors,
    );
  }

  final String id;
  final String mapName;
  final SyncOperationType operation;
  final String? document;
  final DateTime timestamp;
  final Set<String> pendingProviders;
  final Map<String, String> errors;

  bool get isComplete => pendingProviders.isEmpty;

  int get pendingCount => pendingProviders.length;

  SyncQueueEntry copyWith({
    SyncOperationType? operation,
    String? document,
    DateTime? timestamp,
    Set<String>? pendingProviders,
    Map<String, String>? errors,
  }) {
    return SyncQueueEntry(
      id: id,
      mapName: mapName,
      operation: operation ?? this.operation,
      document: document ?? this.document,
      timestamp: timestamp ?? this.timestamp,
      pendingProviders: pendingProviders ?? this.pendingProviders,
      errors: errors ?? this.errors,
    );
  }

  SyncQueueEntry withProviderCompleted(String providerId) {
    final updated = {...pendingProviders}..remove(providerId);
    final updatedErrors = {...errors}..remove(providerId);
    return copyWith(pendingProviders: updated, errors: updatedErrors);
  }

  SyncQueueEntry withProviderError(String providerId, String message) {
    final updated = {...pendingProviders}..remove(providerId);
    final updatedErrors = {...errors, providerId: message};
    return copyWith(pendingProviders: updated, errors: updatedErrors);
  }

  SyncQueueEntry resetForProviders(Iterable<String> providerIds) {
    return copyWith(
      pendingProviders: {...providerIds},
      errors: {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mapName': mapName,
        'operation': operation.name,
        'document': document,
        'timestamp': timestamp.toIso8601String(),
        'pending': pendingProviders.toList(),
        'errors': errors,
      };
}

class CloudAccountData {
  const CloudAccountData({
    required this.providerId,
    required this.displayName,
    required this.metadata,
  });

  factory CloudAccountData.fromJson(Map<String, dynamic> json) => CloudAccountData(
        providerId: json['providerId'] as String,
        displayName: json['displayName'] as String? ?? 'Unknown user',
        metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      );

  final String providerId;
  final String displayName;
  final Map<String, dynamic> metadata;

  CloudAccountData copyWith({
    String? displayName,
    Map<String, dynamic>? metadata,
  }) {
    return CloudAccountData(
      providerId: providerId,
      displayName: displayName ?? this.displayName,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'displayName': displayName,
        'metadata': metadata,
      };
}

class SyncStats {
  const SyncStats({
    this.pending = 0,
    this.lastSuccess,
    this.lastError,
    this.isSyncing = false,
  });

  final int pending;
  final DateTime? lastSuccess;
  final String? lastError;
  final bool isSyncing;

  SyncStats copyWith({
    int? pending,
    DateTime? lastSuccess,
    bool clearSuccess = false,
    String? lastError,
    bool clearError = false,
    bool? isSyncing,
  }) {
    return SyncStats(
      pending: pending ?? this.pending,
      lastSuccess: clearSuccess ? null : (lastSuccess ?? this.lastSuccess),
      lastError: clearError ? null : (lastError ?? this.lastError),
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

class CloudAccountState {
  const CloudAccountState({
    required this.account,
    required this.stats,
  });

  final CloudAccountData account;
  final SyncStats stats;

  CloudAccountState copyWith({
    CloudAccountData? account,
    SyncStats? stats,
  }) {
    return CloudAccountState(
      account: account ?? this.account,
      stats: stats ?? this.stats,
    );
  }
}

class CloudSyncState {
  const CloudSyncState({
    required this.accounts,
    required this.queue,
    required this.status,
    this.activeError,
  });

  factory CloudSyncState.initial() => const CloudSyncState(
        accounts: {},
        queue: [],
        status: CloudSyncStatus.idle,
      );

  final Map<String, CloudAccountState> accounts;
  final List<SyncQueueEntry> queue;
  final CloudSyncStatus status;
  final String? activeError;

  int get pendingOperations => queue.fold<int>(
        0,
        (total, entry) => total + entry.pendingProviders.length,
      );

  bool get hasActiveAccounts => accounts.isNotEmpty;

  CloudSyncState copyWith({
    Map<String, CloudAccountState>? accounts,
    List<SyncQueueEntry>? queue,
    CloudSyncStatus? status,
    String? activeError,
    bool clearError = false,
  }) {
    return CloudSyncState(
      accounts: accounts ?? this.accounts,
      queue: queue ?? this.queue,
      status: status ?? this.status,
      activeError: clearError ? null : (activeError ?? this.activeError),
    );
  }

  String toJson() => jsonEncode({
        'accounts': accounts.map((key, value) => MapEntry(
              key,
              {
                'account': value.account.toJson(),
                'stats': {
                  'pending': value.stats.pending,
                  'lastSuccess': value.stats.lastSuccess?.toIso8601String(),
                  'lastError': value.stats.lastError,
                  'isSyncing': value.stats.isSyncing,
                },
              },
            )),
        'queue': queue.map((e) => e.toJson()).toList(),
        'status': status.name,
        'activeError': activeError,
      });
}
