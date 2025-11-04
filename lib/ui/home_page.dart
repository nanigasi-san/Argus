import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../geo/geo_model.dart';
import '../io/log_entry.dart';
import '../state_machine/state.dart';
import 'settings_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final snapshot = controller.snapshot;
        final showNav = snapshot.status == LocationStateStatus.outer;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Argus'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusBadge(status: snapshot.status),
                const SizedBox(height: 16),
                Text('Current state: ${snapshot.status.name}'),
                if ((snapshot.notes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Notes: ${snapshot.notes}'),
                ],
                const SizedBox(height: 16),
                Text(
                  'Last update: ${snapshot.timestamp.toLocal()}',
                ),
                const SizedBox(height: 8),
                if (showNav) ...[
                  Text(
                    'Distance to boundary: '
                    '${snapshot.distanceToBoundaryM?.toStringAsFixed(1) ?? '-'} m',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bearing to boundary: '
                    '${snapshot.bearingToBoundaryDeg != null ? _formatBearing(snapshot.bearingToBoundaryDeg!) : '-'}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Nearest boundary point: '
                    '${snapshot.nearestBoundaryPoint != null ? _formatLatLng(snapshot.nearestBoundaryPoint!) : '-'}',
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  'Accuracy: '
                  '${snapshot.horizontalAccuracyM?.toStringAsFixed(1) ?? '-'} m',
                ),
                const SizedBox(height: 8),
                Text('GeoJSON loaded: ${controller.geoJsonLoaded}'),
                const SizedBox(height: 24),
                if (controller.lastErrorMessage != null) ...[
                  Material(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                      ),
                      title: Text(
                        controller.lastErrorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: controller.clearError,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => controller.reloadGeoJsonFromPicker(),
                      icon: const Icon(Icons.file_open),
                      label: const Text('Load GeoJSON'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => controller.startMonitoring(),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: controller.logs.isEmpty
                      ? const Text(
                          'Logs will appear once tracking starts.',
                        )
                      : ListView.separated(
                          itemCount: controller.logs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final entry = controller.logs[index];
                            return _LogCard(entry: entry);
                          },
                        ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => controller.reloadGeoJsonFromPicker(),
            icon: const Icon(Icons.map),
            label: const Text('GeoJSON'),
          ),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final LocationStateStatus status;

  Color _color(LocationStateStatus status) {
    switch (status) {
      case LocationStateStatus.inner:
        return Colors.green;
      case LocationStateStatus.near:
        return Colors.orange;
      case LocationStateStatus.outerPending:
        return Colors.deepOrange;
      case LocationStateStatus.outer:
        return Colors.red;
      case LocationStateStatus.gpsBad:
        return Colors.grey;
      case LocationStateStatus.waitGeoJson:
        return Colors.blueGrey;
      case LocationStateStatus.init:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(status.name),
      backgroundColor: _color(status).withValues(alpha: 0.15),
      side: BorderSide(color: _color(status)),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.entry});

  final AppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = _borderColor(entry.level, theme);
    final backgroundColor = borderColor.withValues(alpha: 0.08);
    final icon = _iconForLevel(entry.level);
    final normalized =
        entry.message.replaceAll('\r\n', '\n').trimRight();
    final timestamp =
        entry.timestamp.toLocal().toString().split('.').first;

    return Card(
      elevation: 0,
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: borderColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  entry.tag,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: borderColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  timestamp,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              normalized.isEmpty ? '(no message)' : normalized,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _borderColor(AppLogLevel level, ThemeData theme) {
    switch (level) {
      case AppLogLevel.error:
        return theme.colorScheme.error;
      case AppLogLevel.warning:
        return theme.colorScheme.tertiary;
      case AppLogLevel.debug:
        return theme.colorScheme.outlineVariant;
      case AppLogLevel.info:
        return theme.colorScheme.primary;
    }
  }

  IconData? _iconForLevel(AppLogLevel level) {
    switch (level) {
      case AppLogLevel.error:
        return Icons.error_outline;
      case AppLogLevel.warning:
        return Icons.warning_amber_outlined;
      case AppLogLevel.info:
        return Icons.info_outline;
      case AppLogLevel.debug:
        return Icons.notes;
    }
  }
}

String _formatBearing(double bearing) {
  const labels = <String>[
    'N',
    'NE',
    'E',
    'SE',
    'S',
    'SW',
    'W',
    'NW',
  ];
  final normalized = (bearing % 360 + 360) % 360;
  final index = ((normalized + 22.5) ~/ 45) % labels.length;
  return '${normalized.toStringAsFixed(0)}deg (${labels[index]})';
}

String _formatLatLng(LatLng point) {
  return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
}
