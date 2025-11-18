import 'cloud_service.dart';

class CloudServiceState {
  const CloudServiceState({
    required this.service,
    required this.connected,
    this.connecting = false,
    this.userLabel,
    this.error,
  });

  final CloudService service;
  final bool connected;
  final bool connecting;
  final String? userLabel;
  final String? error;

  String get label => userLabel ?? service.name;

  CloudServiceState copyWith({
    bool? connected,
    bool? connecting,
    String? userLabel,
    String? error,
  }) {
    return CloudServiceState(
      service: service,
      connected: connected ?? this.connected,
      connecting: connecting ?? this.connecting,
      userLabel: userLabel ?? this.userLabel,
      error: error,
    );
  }
}

class CloudSyncState {
  const CloudSyncState({
    required this.services,
    required this.pendingOperations,
    required this.syncing,
    this.lastSyncedAt,
    this.lastError,
  });

  final Map<CloudServiceType, CloudServiceState> services;
  final int pendingOperations;
  final bool syncing;
  final DateTime? lastSyncedAt;
  final String? lastError;

  int get connectedServices =>
      services.values.where((state) => state.connected).length;

  bool get hasActiveService => connectedServices > 0;

  CloudSyncState copyWith({
    Map<CloudServiceType, CloudServiceState>? services,
    int? pendingOperations,
    bool? syncing,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return CloudSyncState(
      services: services ?? this.services,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      syncing: syncing ?? this.syncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}
