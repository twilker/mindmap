import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cloud_sync.dart';
import '../sync/cloud_sync_models.dart';

class CloudSyncDialog extends ConsumerStatefulWidget {
  const CloudSyncDialog({super.key});

  @override
  ConsumerState<CloudSyncDialog> createState() => _CloudSyncDialogState();
}

class _CloudSyncDialogState extends ConsumerState<CloudSyncDialog> {
  final Set<String> _busyProviders = {};

  void _setBusy(String id, bool busy) {
    setState(() {
      if (busy) {
        _busyProviders.add(id);
      } else {
        _busyProviders.remove(id);
      }
    });
  }

  Future<void> _connect(String providerId) async {
    _setBusy(providerId, true);
    try {
      await ref.read(cloudSyncControllerProvider.notifier).connect(providerId);
    } finally {
      if (mounted) {
        _setBusy(providerId, false);
      }
    }
  }

  Future<void> _disconnect(String providerId) async {
    _setBusy(providerId, true);
    try {
      await ref
          .read(cloudSyncControllerProvider.notifier)
          .disconnect(providerId);
    } finally {
      if (mounted) {
        _setBusy(providerId, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cloudSyncControllerProvider);
    final providers = ref.watch(cloudSyncProvidersProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Cloud synchronization'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manage the cloud providers used to synchronize your mind maps.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  final provider = providers.values.elementAt(index);
                  final accountState = state.accounts[provider.id];
                  final connected = accountState != null;
                  final stats = accountState?.stats;
                  final busy = _busyProviders.contains(provider.id);
                  return _ProviderTile(
                    providerName: provider.name,
                    connected: connected,
                    stats: stats,
                    onConnect: busy ? null : () => _connect(provider.id),
                    onDisconnect:
                        busy ? null : () => _disconnect(provider.id),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 24),
                itemCount: providers.length,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.providerName,
    required this.connected,
    this.stats,
    this.onConnect,
    this.onDisconnect,
  });

  final String providerName;
  final bool connected;
  final SyncStats? stats;
  final VoidCallback? onConnect;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                providerName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (connected)
              FilledButton.tonal(
                onPressed: onDisconnect,
                child: const Text('Disconnect'),
              )
            else
              FilledButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Connect'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (connected && stats != null)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _InfoChip(
                icon: Icons.pending_actions,
                label: '${stats!.pending} pending',
              ),
              if (stats!.lastSuccess != null)
                _InfoChip(
                  icon: Icons.schedule,
                  label: 'Last sync ${_formatRelative(stats!.lastSuccess!)}',
                ),
              if (stats!.lastError != null)
                _InfoChip(
                  icon: Icons.error_outline,
                  label: stats!.lastError!,
                ),
            ],
          )
        else
          Text(
            connected
                ? 'Connected and waiting for updates.'
                : 'Not connected yet. Tap connect to start syncing.',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }

  static String _formatRelative(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }
    return '${difference.inDays}d ago';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
