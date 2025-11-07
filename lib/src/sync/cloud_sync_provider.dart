import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'cloud_sync_models.dart';

class CloudProviderContext {
  const CloudProviderContext({
    required this.secureStorage,
    required this.httpClientFactory,
  });

  final FlutterSecureStorage secureStorage;
  final http.Client Function() httpClientFactory;
}

abstract class CloudSyncProvider {
  String get id;

  String get name;

  Future<CloudAccountData?> connect(CloudProviderContext context);

  Future<void> disconnect(
    CloudProviderContext context,
    CloudAccountData? existingAccount,
  );

  Future<CloudAccountData?> restore(
    CloudProviderContext context,
    CloudAccountData account,
  );

  Future<CloudAccountData> performOperation(
    CloudProviderContext context,
    CloudAccountData account,
    SyncQueueEntry entry,
  );
}
