import 'package:flutter/material.dart';

enum CloudServiceType { googleDrive }

class CloudService {
  const CloudService({
    required this.type,
    required this.name,
    required this.icon,
  });

  final CloudServiceType type;
  final String name;
  final IconData icon;
}

const cloudServices = <CloudServiceType, CloudService>{
  CloudServiceType.googleDrive: CloudService(
    type: CloudServiceType.googleDrive,
    name: 'Google Drive',
    icon: Icons.cloud_circle,
  ),
};
