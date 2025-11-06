import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cloud_sync.dart';
import '../sync/cloud_sync_models.dart';
import 'cloud_sync_dialog.dart';

class CloudSyncStatusChip extends ConsumerWidget {
  const CloudSyncStatusChip({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cloudSyncControllerProvider);
    final theme = Theme.of(context);
    final status = state.status;
    final pending = state.pendingOperations;
    final message = _statusMessage(status, pending, state.activeError);
    final icon = _iconForStatus(status, pending);
    final colors = _colorsForStatus(theme, status);

    return Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: () {
          showDialog<void>(
            context: context,
            builder: (context) => const CloudSyncDialog(),
          );
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 16,
            vertical: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colors.foreground),
              if (!compact) ...[
                const SizedBox(width: 8),
                Text(
                  message,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  _StatusColors _colorsForStatus(ThemeData theme, CloudSyncStatus status) {
    switch (status) {
      case CloudSyncStatus.idle:
        return _StatusColors(
          background: theme.colorScheme.primaryContainer,
          foreground: theme.colorScheme.onPrimaryContainer,
        );
      case CloudSyncStatus.syncing:
        return _StatusColors(
          background: theme.colorScheme.secondaryContainer,
          foreground: theme.colorScheme.onSecondaryContainer,
        );
      case CloudSyncStatus.offline:
        return _StatusColors(
          background: theme.colorScheme.surfaceContainerHighest,
          foreground: theme.colorScheme.onSurfaceVariant,
        );
      case CloudSyncStatus.error:
        return _StatusColors(
          background: theme.colorScheme.errorContainer,
          foreground: theme.colorScheme.onErrorContainer,
        );
    }
  }

  IconData _iconForStatus(CloudSyncStatus status, int pending) {
    switch (status) {
      case CloudSyncStatus.idle:
        return pending > 0 ? Icons.cloud_queue : Icons.cloud_done;
      case CloudSyncStatus.syncing:
        return Icons.sync;
      case CloudSyncStatus.offline:
        return Icons.cloud_off;
      case CloudSyncStatus.error:
        return Icons.error_outline;
    }
  }

  String _statusMessage(CloudSyncStatus status, int pending, String? error) {
    switch (status) {
      case CloudSyncStatus.idle:
        if (pending > 0) {
          return '$pending pending';
        }
        return 'Synced';
      case CloudSyncStatus.syncing:
        return pending > 0 ? 'Syncing ($pending)' : 'Syncing';
      case CloudSyncStatus.offline:
        return pending > 0 ? 'Offline ($pending)' : 'Offline';
      case CloudSyncStatus.error:
        return error ?? 'Sync error';
    }
  }
}

class _StatusColors {
  const _StatusColors({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}
