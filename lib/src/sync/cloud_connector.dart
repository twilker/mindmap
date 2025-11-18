import 'cloud_service.dart';
import 'cloud_sync_operation.dart';
import 'cloud_sync_state.dart';

abstract class CloudConnector {
  CloudServiceType get type;
  CloudServiceState get state;

  Future<void> initialize();
  Future<void> connect();
  Future<void> disconnect();
  Future<bool> applyOperation(CloudSyncOperation operation);
  void dispose() {}
}
