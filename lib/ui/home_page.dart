import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../geo/geo_model.dart';
import '../io/log_entry.dart';
import '../state_machine/state.dart';
import 'qr_scanner_page.dart';
import 'settings_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final snapshot = controller.snapshot;
        final showNav = controller.developerMode ||
            snapshot.status == LocationStateStatus.outer;
        // エラーはSnackbarで出して自動フェード
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final msg = controller.lastErrorMessage;
          if (msg != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
            controller.clearError();
          }
        });

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            toolbarHeight: 64,
            elevation: 0,
            title: const _BrandHeader(),
            actions: [
              const _OverflowMenu(),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: controller.developerMode
                ? Column(
                    children: [
                      const SizedBox(height: 8),
                      // 開発者モードの時は上部を縮小
                      Flexible(
                        flex: 3,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 16),
                              _GpsAccuracyInfo(accuracyM: snapshot.horizontalAccuracyM),
                              const SizedBox(height: 12),
                              _LargeStatusDisplay(
                                status: snapshot.status,
                                onTap: snapshot.status ==
                                        LocationStateStatus.waitStart
                                    ? () => controller.startMonitoring()
                                    : null,
                              ),
                              if (snapshot.status ==
                                  LocationStateStatus.waitStart) ...[
                                const SizedBox(height: 16),
                                _StartCallToAction(
                                  onPressed: controller.startMonitoring,
                                  geoJsonReady: controller.geoJsonLoaded,
                                ),
                              ],
                              // GeoJSONファイル状態を表示
                              const SizedBox(height: 24),
                              _GeoJsonStatusDisplay(
                                geoJsonLoaded: controller.geoJsonLoaded,
                                fileName: controller.geoJsonFileName,
                              ),
                              // developerモードでは常に方角と距離を表示
                              if (showNav) ...[
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
                                  'GeoJSON loaded: ${controller.geoJsonLoaded}'),
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
                      const SizedBox(height: 8),
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
                                _GpsAccuracyInfo(accuracyM: snapshot.horizontalAccuracyM),
                                const SizedBox(height: 12),
                                _LargeStatusDisplay(
                                  status: snapshot.status,
                                  onTap: snapshot.status ==
                                          LocationStateStatus.waitStart
                                      ? () => controller.startMonitoring()
                                      : null,
                                ),
                                if (snapshot.status ==
                                    LocationStateStatus.waitStart) ...[
                                  const SizedBox(height: 16),
                                  _StartCallToAction(
                                    onPressed: controller.startMonitoring,
                                    geoJsonReady: controller.geoJsonLoaded,
                                  ),
                                ],
                                // GeoJSONファイル状態を表示
                                const SizedBox(height: 24),
                                _GeoJsonStatusDisplay(
                                  geoJsonLoaded: controller.geoJsonLoaded,
                                  fileName: controller.geoJsonFileName,
                                ),
                                // outerの時に方角と距離を表示
                                if (showNav &&
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
                      // エラー表示はSnackbarに移行済み
                    ],
                  ),
          ),
          // 主要操作は下部に常設
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _BottomActions(
              isWaitStart: snapshot.status == LocationStateStatus.waitStart,
              geoJsonReady: controller.geoJsonLoaded,
              onStart: controller.startMonitoring,
              onLoadGeoJson: controller.reloadGeoJsonFromPicker,
              onOpenQr: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QrScannerPage()),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('icon.png', width: 32, height: 32),
        const SizedBox(width: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ARGUS',
              style: theme.textTheme.titleLarge?.copyWith(
                letterSpacing: 2.0,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GpsAccuracyInfo extends StatelessWidget {
  const _GpsAccuracyInfo({required this.accuracyM});

  final double? accuracyM;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.my_location, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          'GPS精度: ${accuracyM?.toStringAsFixed(1) ?? '-'} m',
          style: TextStyle(fontSize: 13, color: color),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.isWaitStart,
    required this.geoJsonReady,
    required this.onStart,
    required this.onLoadGeoJson,
    required this.onOpenQr,
  });

  final bool isWaitStart;
  final bool geoJsonReady;
  final VoidCallback onStart;
  final VoidCallback onLoadGeoJson;
  final VoidCallback onOpenQr;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isWaitStart)
          _StartCallToAction(onPressed: onStart, geoJsonReady: geoJsonReady)
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start monitoring'),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onLoadGeoJson,
                icon: const Icon(Icons.map),
                label: const Text('Load GeoJSON'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onOpenQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Read QR code'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      itemBuilder: (context) => const [
        PopupMenuItem(value: 1, child: Text('Settings')),
      ],
      onSelected: (value) {
        if (value == 1) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          );
        }
      },
    );
  }
}

class _StartCallToAction extends StatelessWidget {
  const _StartCallToAction({
    required this.onPressed,
    required this.geoJsonReady,
  });

  final VoidCallback onPressed;
  final bool geoJsonReady;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintText = geoJsonReady
        ? 'GeoJSON ready. Argus can run without network.'
        : 'Load a GeoJSON from file or QR to work offline.';
    final hintColor = theme.colorScheme.onSurfaceVariant;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              HapticFeedback.mediumImpact();
              onPressed();
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 32),
            label: const Text('Start monitoring'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              textStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              geoJsonReady ? Icons.offline_pin : Icons.map_outlined,
              size: 16,
              color: hintColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                hintText,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hintColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GeoJsonStatusDisplay extends StatelessWidget {
  const _GeoJsonStatusDisplay({
    required this.geoJsonLoaded,
    this.fileName,
  });

  final bool geoJsonLoaded;
  final String? fileName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!geoJsonLoaded) {
      return Wrap(
        alignment: WrapAlignment.center,
        children: [
          Chip(
            avatar: Icon(
              Icons.info_outline,
              size: 16,
              color: theme.colorScheme.onSurface,
            ),
            label: const Text('Please select GeoJSON file'),
          ),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        Chip(
          avatar: const Icon(Icons.map, size: 16),
          label: Text(fileName ?? 'GeoJSON'),
          labelStyle: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
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

  String _statusCode(LocationStateStatus status) {
    switch (status) {
      case LocationStateStatus.inner:
        return 'INNER';
      case LocationStateStatus.near:
        return 'NEAR';
      case LocationStateStatus.outerPending:
        return 'OUTER PENDING';
      case LocationStateStatus.outer:
        return 'OUTER';
      case LocationStateStatus.gpsBad:
        return 'GPS BAD';
      case LocationStateStatus.waitGeoJson:
        return 'WAIT GEOJSON';
      case LocationStateStatus.waitStart:
        return 'WAIT START';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    final statusText = _statusText(status);
    final statusCode = _statusCode(status);
    final screenSize = MediaQuery.of(context).size;
    final circleSize = (screenSize.shortestSide * 0.75)
        .clamp(220.0, screenSize.shortestSide * 0.9)
        .toDouble();

    Widget buildLabel(String text, TextStyle style) {
      return SizedBox(
        width: circleSize * 0.78,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
      );
    }

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
            buildLabel(
              statusText,
              TextStyle(
                fontSize: circleSize * 0.2,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            buildLabel(
              statusCode,
              TextStyle(
                fontSize: circleSize *
                    (status == LocationStateStatus.waitGeoJson ? 0.08 : 0.09),
                color: color.withValues(alpha: 0.75),
                fontWeight: FontWeight.w700,
                letterSpacing:
                    status == LocationStateStatus.waitGeoJson ? 0.8 : 1.2,
              ),
            ),
          ],
        ),
      ),
    );

    // waitStartの時はタップ可能にする
    if (onTap != null) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: circleWidget,
        ),
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
