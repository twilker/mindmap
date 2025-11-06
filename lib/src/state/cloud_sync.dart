import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../sync/cloud_sync_controller.dart';
import '../sync/cloud_sync_models.dart';
import '../sync/cloud_sync_persistence.dart';
import '../sync/cloud_sync_provider.dart';
import '../sync/google_drive_sync_provider.dart';
import 'mind_map_storage.dart';

final flutterSecureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  throw UnimplementedError('Secure storage must be overridden at runtime.');
});

final cloudSyncPersistenceProvider = Provider<CloudSyncPersistence>((ref) {
  throw UnimplementedError('Cloud sync persistence must be overridden.');
});

final cloudSyncProvidersProvider = Provider<Map<String, CloudSyncProvider>>((ref) {
  return {
    GoogleDriveSyncProvider().id: GoogleDriveSyncProvider(),
  };
});

final cloudSyncControllerProvider =
    StateNotifierProvider<CloudSyncController, CloudSyncState>((ref) {
  final persistence = ref.watch(cloudSyncPersistenceProvider);
  final providers = ref.watch(cloudSyncProvidersProvider);
  final storage = ref.watch(mindMapStorageProvider);
  final secureStorage = ref.watch(flutterSecureStorageProvider);
  return CloudSyncController(
    persistence: persistence,
    providers: providers,
    storage: storage,
    secureStorage: secureStorage,
  );
});
