import 'dart:convert';

enum CloudSyncOperationType { create, update, delete }

class CloudSyncOperation {
  CloudSyncOperation({
    required this.mapName,
    required this.type,
    required this.document,
    DateTime? queuedAt,
  }) : queuedAt = queuedAt ?? DateTime.now();

  final String mapName;
  final CloudSyncOperationType type;
  final String document;
  final DateTime queuedAt;

  Map<String, dynamic> toJson() => {
    'mapName': mapName,
    'type': type.name,
    'document': document,
    'queuedAt': queuedAt.toIso8601String(),
  };

  static CloudSyncOperation fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return CloudSyncOperation(
      mapName: map['mapName'] as String,
      type: CloudSyncOperationType.values.firstWhere(
        (value) => value.name == map['type'],
        orElse: () => CloudSyncOperationType.update,
      ),
      document: map['document'] as String,
      queuedAt: DateTime.tryParse(map['queuedAt'] as String? ?? ''),
    );
  }
}
