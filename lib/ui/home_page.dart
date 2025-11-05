import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../geo/geo_model.dart';
import '../io/log_entry.dart';
import '../state_machine/state.dart';
import 'settings_page.dart';

/// 監視状態と操作を表示するメイン画面。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final snapshot = controller.snapshot;
        final shouldShowNavigation = controller.isDeveloperModeEnabled ||
            snapshot.status == LocationStateStatus.outer;
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
            child: controller.isDeveloperModeEnabled
                ? Column(
                    children: [
                      // 開発者モードの時は上部を縮小
                      Flexible(
                        flex: 3,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 16),
                              // GPS精度を常に表示
                              Text(
                                'GPS精度: ${snapshot.horizontalAccuracyM?.toStringAsFixed(1) ?? '-'} m',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              if (snapshot.status ==
                                  LocationStateStatus.waitStart) ...[
                                Text(
                                  '↓ Press this button to start',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                              ],
                              _LargeStatusDisplay(
                                status: snapshot.status,
                                onTap: snapshot.status ==
                                        LocationStateStatus.waitStart
                                    ? () => controller.startMonitoring()
                                    : null,
                              ),
                              // GeoJSONファイル状態を表示
                              const SizedBox(height: 24),
                              _GeoJsonStatusDisplay(
                                hasGeoJson: controller.hasGeoJson,
                                fileName: controller.geoJsonFileName,
                              ),
                              // developerモードでは常に方角と距離を表示
                              if (shouldShowNavigation) ...[
                                const SizedBox(height: 24),
                                Text(
                                  '境界までの距離: '
                                  '${snapshot.distanceToBoundaryM?.toStringAsFixed(1) ?? '-'} m',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '方角: '
                                  '${snapshot.bearingToBoundaryDeg != null ? _formatBearing(snapshot.bearingToBoundaryDeg!) : '-'}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // 詳細情報セクション（開発者モードのみ）
                      const Divider(),
                      const SizedBox(height: 8),
                      Flexible(
                        flex: 4,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                              // Developerモードでは常に距離・方角・境界点を表示
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
                              Text(
                                'Accuracy: '
                                '${snapshot.horizontalAccuracyM?.toStringAsFixed(1) ?? '-'} m',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                  'GeoJSON loaded: ${controller.hasGeoJson ? 'Yes' : 'No'}'),
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
                                      icon: const Icon(Icons.close,
                                          color: Colors.red),
                                      onPressed: controller.clearError,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                              const SizedBox(height: 24),
                              if (controller.logs.isNotEmpty) ...[
                                const Text(
                                  'Logs:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...controller.logs
                                    .take(5)
                                    .map((entry) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: _LogCard(entry: entry),
                                        )),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      // 中央に大きなステータス表示
                      // waitStartの時はタップ可能でSTARTボタンとして機能
                      Expanded(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                              // GPS精度を常に表示
                              Text(
                                'GPS精度: ${snapshot.horizontalAccuracyM?.toStringAsFixed(1) ?? '-'} m',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              if (snapshot.status ==
                                  LocationStateStatus.waitStart) ...[
                                Text(
                                  '↓ Press this button to start',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                              ],
                              _LargeStatusDisplay(
                                status: snapshot.status,
                                onTap: snapshot.status ==
                                        LocationStateStatus.waitStart
                                    ? () => controller.startMonitoring()
                                    : null,
                              ),
                              // GeoJSONファイル状態を表示
                              const SizedBox(height: 24),
                              _GeoJsonStatusDisplay(
                                hasGeoJson: controller.hasGeoJson,
                                fileName: controller.geoJsonFileName,
                              ),
                              // outerの時に方角と距離を表示
                              if (shouldShowNavigation &&
                                  snapshot.status ==
                                      LocationStateStatus.outer) ...[
                                const SizedBox(height: 24),
                                Text(
                                  '境界までの距離: '
                                  '${snapshot.distanceToBoundaryM?.toStringAsFixed(1) ?? '-'} m',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '方角: '
                                  '${snapshot.bearingToBoundaryDeg != null ? _formatBearing(snapshot.bearingToBoundaryDeg!) : '-'}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      ),
                      // 開発者モードでない場合は、エラーメッセージのみ表示
                      if (controller.lastErrorMessage != null) ...[
                        const SizedBox(height: 16),
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
                      ],
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

class _GeoJsonStatusDisplay extends StatelessWidget {
  const _GeoJsonStatusDisplay({
    required this.hasGeoJson,
    this.fileName,
  });

  final bool hasGeoJson;
  final String? fileName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!hasGeoJson) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'Please select GeoJSON file',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.map,
          size: 16,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            fileName ?? 'GeoJSON',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _LargeStatusDisplay extends StatelessWidget {
  const _LargeStatusDisplay({
    required this.status,
    this.onTap,
  });

  final LocationStateStatus status;
  final VoidCallback? onTap;

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
      case LocationStateStatus.waitStart:
        return Colors.blue;
    }
  }

  String _statusText(LocationStateStatus status) {
    switch (status) {
      case LocationStateStatus.inner:
        return '内側';
      case LocationStateStatus.near:
        return '近接';
      case LocationStateStatus.outerPending:
        return '外側待機';
      case LocationStateStatus.outer:
        return '外側';
      case LocationStateStatus.gpsBad:
        return 'GPS不良';
      case LocationStateStatus.waitGeoJson:
        return 'GeoJSON待機';
      case LocationStateStatus.waitStart:
        return 'スタート待機';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    final statusText = _statusText(status);
    final screenSize = MediaQuery.of(context).size;
    final circleSize = screenSize.width * 0.7;

    final circleWidget = Container(
      width: circleSize,
      height: circleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
        border: Border.all(
          color: color,
          width: 4,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: circleSize * 0.2,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              status.name.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: circleSize * 0.08,
                color: color.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );

    // waitStartの時はタップ可能にする
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: circleWidget,
      );
    }

    return circleWidget;
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
    final normalized = entry.message.replaceAll('\r\n', '\n').trimRight();
    final timestamp = entry.timestamp.toLocal().toString().split('.').first;

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
