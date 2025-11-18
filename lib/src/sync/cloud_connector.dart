import 'cloud_service.dart';
import 'cloud_sync_operation.dart';
import 'cloud_sync_state.dart';

class CloudSyncedDocument {
  const CloudSyncedDocument({required this.mapName, required this.document});

  final String mapName;
  final String document;
}

abstract class CloudConnector {
  CloudServiceType get type;
  CloudServiceState get state;

  Future<void> initialize();
  Future<void> connect();
  Future<void> disconnect();
  Future<List<CloudSyncedDocument>> fetchRemoteDocuments();
  Future<bool> applyOperation(CloudSyncOperation operation);
  void dispose() {}
}
