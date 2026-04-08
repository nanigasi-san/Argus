import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../platform/permission_coordinator.dart';

class MonitoringPermissionCard extends StatelessWidget {
  const MonitoringPermissionCard({
    super.key,
    required this.permissionState,
    required this.onOpenMonitoringSetup,
    required this.onRequestNotifications,
    required this.onRefresh,
  });

  final MonitoringPermissionState permissionState;
  final AsyncCallback onOpenMonitoringSetup;
  final AsyncCallback onRequestNotifications;
  final AsyncCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final needsMonitoringSetup = !permissionState.canStartMonitoring;
    final needsNotifications = !permissionState.notificationGranted;

    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  needsMonitoringSetup
                      ? Icons.shield_outlined
                      : Icons.notifications_none,
                  color: needsMonitoringSetup
                      ? colorScheme.primary
                      : colorScheme.secondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        needsMonitoringSetup
                            ? 'バックグラウンド位置情報の設定が必要です'
                            : '通知権限を許可すると警告を見逃しにくくなります',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        permissionState.setupSummary,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  label: '通知',
                  granted: permissionState.notificationGranted,
                ),
                _StatusChip(
                  label: '使用中の位置情報',
                  granted: permissionState.locationWhenInUseGranted,
                ),
                _StatusChip(
                  label: '常に許可',
                  granted: permissionState.locationAlwaysGranted,
                ),
                _StatusChip(
                  label: '端末の位置情報サービス',
                  granted: permissionState.locationServicesEnabled,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (needsMonitoringSetup)
                  FilledButton.icon(
                    onPressed: onOpenMonitoringSetup,
                    icon: const Icon(Icons.gps_fixed),
                    label: const Text('開示を確認して設定へ進む'),
                  ),
                if (needsNotifications)
                  OutlinedButton.icon(
                    onPressed: onRequestNotifications,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('通知を許可'),
                  ),
                TextButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('状態を更新'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.granted,
  });

  final String label;
  final bool granted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor =
        granted ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final backgroundColor = granted
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHigh;

    return Chip(
      avatar: Icon(
        granted ? Icons.check_circle_outline : Icons.error_outline,
        size: 18,
        color: foregroundColor,
      ),
      label: Text(label),
      labelStyle: TextStyle(color: foregroundColor),
      backgroundColor: backgroundColor,
      side: BorderSide.none,
    );
  }
}
