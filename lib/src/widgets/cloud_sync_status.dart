import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/cloud_service.dart';
import '../sync/cloud_sync_notifier.dart';
import '../sync/cloud_sync_state.dart';

class CloudSyncStatus extends ConsumerWidget {
  const CloudSyncStatus({super.key, this.compact = false, this.onTap});

  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(cloudSyncNotifierProvider);
    final pending = syncState.pendingOperations;
    final connected = syncState.connectedServices;
    final textTheme = Theme.of(context).textTheme;
    final label = _buildLabel(context, syncState, connected, pending);
    final iconColor = syncState.hasActiveService
        ? Colors.green.shade600
        : Theme.of(context).colorScheme.onSurface.withOpacity(0.7);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              syncState.syncing ? Icons.sync : Icons.cloud_done,
              size: compact ? 18 : 20,
              color: iconColor,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: textTheme.labelLarge),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(syncState),
                    style: textTheme.bodySmall?.copyWith(
                      color: textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
            if (pending > 0) ...[
              const SizedBox(width: 10),
              _Badge(label: '$pending'),
            ],
          ],
        ),
      ),
    );
  }

  String _buildLabel(
    BuildContext context,
    CloudSyncState state,
    int connected,
    int pending,
  ) {
    if (connected == 0) {
      return 'Cloud sync disabled';
    }
    if (state.syncing) {
      return 'Syncing $pending change${pending == 1 ? '' : 's'}';
    }
    if (pending > 0) {
      return '$pending change${pending == 1 ? '' : 's'} queued';
    }
    if (state.lastSyncedAt != null) {
      final time = TimeOfDay.fromDateTime(state.lastSyncedAt!);
      return 'Last sync ${time.format(context)}';
    }
    return 'Synced and up to date';
  }

  String _subtitle(CloudSyncState state) {
    if (state.lastError != null) {
      return state.lastError!;
    }
    if (state.services.isEmpty) {
      return 'No cloud services configured';
    }
    final connected = state.services.values.where((s) => s.connected);
    if (connected.isEmpty) {
      return 'Connect a cloud service';
    }
    final names = connected.map((s) => s.label).join(', ');
    return 'Connected to $names';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: colorScheme.primary),
      ),
    );
  }
}

Future<void> showCloudSyncSheet(BuildContext context) async {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => const _CloudSyncSheet(),
  );
}

class _CloudSyncSheet extends ConsumerWidget {
  const _CloudSyncSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cloudSyncNotifierProvider);
    final controller = ref.read(cloudSyncNotifierProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cloud synchronization',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'Connect a cloud provider to back up your mind maps. Changes are queued when offline and synced when you reconnect.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          for (final entry in state.services.entries)
            _CloudServiceTile(
              serviceState: entry.value,
              onConnect: () => controller.connect(entry.key),
              onDisconnect: () => controller.disconnect(entry.key),
            ),
          if (state.lastError != null) ...[
            const SizedBox(height: 12),
            Text(
              state.lastError!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _CloudServiceTile extends StatelessWidget {
  const _CloudServiceTile({
    required this.serviceState,
    required this.onConnect,
    required this.onDisconnect,
  });

  final CloudServiceState serviceState;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final subtitle = serviceState.connected
        ? 'Connected as ${serviceState.label}'
        : 'Tap connect to enable';
    final statusColor = serviceState.connected
        ? Colors.green
        : Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    final error = serviceState.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(serviceState.service.icon, color: statusColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    serviceState.service.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    error ?? subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: error != null
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(
                              context,
                            ).textTheme.bodySmall?.color?.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (serviceState.connected)
              OutlinedButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.logout),
                label: const Text('Disconnect'),
              )
            else
              FilledButton.icon(
                onPressed: serviceState.connecting ? null : onConnect,
                icon: const Icon(Icons.cloud_sync),
                label: Text(
                  serviceState.connecting ? 'Connecting…' : 'Connect',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
