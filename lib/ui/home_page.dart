import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../app_links.dart';
import '../geo/geo_model.dart';
import '../io/log_entry.dart';
import '../state_machine/state.dart';
import 'background_location_disclosure_page.dart';
import 'monitoring_permission_card.dart';
import 'qr_generator_page.dart';
import 'qr_scanner_page.dart';
import 'settings_page.dart';

enum _LoadFileAction {
  geoJson,
  qrImage,
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final snapshot = controller.snapshot;
        final showNav = (controller.developerMode ||
                snapshot.status == LocationStateStatus.outer) &&
            controller.navigationEnabled;
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

        final viewPadding = MediaQuery.viewPaddingOf(context);
        final permissionCard = controller.shouldShowPermissionSetupCard
            ? MonitoringPermissionCard(
                permissionState: controller.monitoringPermissionState,
                onOpenMonitoringSetup: () async {
                  await showBackgroundLocationDisclosure(context);
                },
                onRequestNotifications:
                    controller.requestNotificationPermission,
                onRefresh: controller.refreshMonitoringPermissionState,
              )
            : null;

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
          body: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + viewPadding.bottom),
              child: controller.developerMode
                  ? Column(
                      children: [
                        const SizedBox(height: 8),
                        if (permissionCard != null) ...[
                          permissionCard,
                          const SizedBox(height: 16),
                        ],
                        // 開発者モードの時は上部を縮小
                        Flexible(
                          flex: 3,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 16),
                                _GpsAccuracyInfo(
                                    accuracyM: snapshot.horizontalAccuracyM),
                                const SizedBox(height: 6),
                                _FileNameInfo(
                                  fileName: controller.geoJsonFileName,
                                  loaded: controller.geoJsonLoaded,
                                ),
                                const SizedBox(height: 12),
                                _LargeStatusDisplay(
                                  status: snapshot.status,
                                  onTap: snapshot.status ==
                                          LocationStateStatus.waitStart
                                      ? () {
                                          if (controller.canStartMonitoring) {
                                            controller.startMonitoring();
                                          } else {
                                            showBackgroundLocationDisclosure(
                                                context);
                                          }
                                        }
                                      : null,
                                ),
                                // ヒントは円内に描画するため外側には出さない
                                // GeoJSONファイル状態は円の上へ移動済み
                                const SizedBox(height: 12),
                                _BottomActions(
                                  isWaitStart: snapshot.status ==
                                      LocationStateStatus.waitStart,
                                  geoJsonReady: controller.geoJsonLoaded,
                                  onLoadFile: () {
                                    _showLoadFileSheet(context, controller);
                                  },
                                  onOpenQr: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const QrScannerPage(),
                                      ),
                                    );
                                  },
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
                                  if (snapshot.status ==
                                      LocationStateStatus.outer) ...[
                                    const SizedBox(height: 16),
                                    _AlarmSnoozeAction(
                                      isSnoozed: controller.isAlarmSnoozed,
                                      onPressed: controller.canSnoozeAlarm
                                          ? controller.snoozeAlarmForOneMinute
                                          : null,
                                    ),
                                  ],
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
                                Text('現在の状態: ${snapshot.status.name}'),
                                if ((snapshot.notes ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text('メモ: ${snapshot.notes}'),
                                ],
                                const SizedBox(height: 16),
                                Text(
                                  '最終更新: ${snapshot.timestamp.toLocal()}',
                                ),
                                const SizedBox(height: 8),
                                // Developerモードでは常に距離・方角・境界点を表示
                                Text(
                                  '境界までの距離: '
                                  '${snapshot.distanceToBoundaryM?.toStringAsFixed(1) ?? '-'} m',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '方角: '
                                  '${snapshot.bearingToBoundaryDeg != null ? _formatBearing(snapshot.bearingToBoundaryDeg!) : '-'}',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '最寄り境界点: '
                                  '${snapshot.nearestBoundaryPoint != null ? _formatLatLng(snapshot.nearestBoundaryPoint!) : '-'}',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'GPS精度: '
                                  '${snapshot.horizontalAccuracyM?.toStringAsFixed(1) ?? '-'} m',
                                ),
                                const SizedBox(height: 8),
                                Text(
                                    'GeoJSON読込済み: ${controller.geoJsonLoaded}'),
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
                                        style:
                                            const TextStyle(color: Colors.red),
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
                                    'ログ:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...controller.logs
                                      .take(5)
                                      .map((entry) => Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 8),
                                            child: _LogCard(entry: entry),
                                          )),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _CreditFooter(),
                      ],
                    )
                  : Column(
                      children: [
                        const SizedBox(height: 8),
                        if (permissionCard != null) ...[
                          permissionCard,
                          const SizedBox(height: 16),
                        ],
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
                                  _GpsAccuracyInfo(
                                      accuracyM: snapshot.horizontalAccuracyM),
                                  const SizedBox(height: 6),
                                  _FileNameInfo(
                                    fileName: controller.geoJsonFileName,
                                    loaded: controller.geoJsonLoaded,
                                  ),
                                  const SizedBox(height: 12),
                                  _LargeStatusDisplay(
                                    status: snapshot.status,
                                    onTap: snapshot.status ==
                                            LocationStateStatus.waitStart
                                        ? () {
                                            if (controller.canStartMonitoring) {
                                              controller.startMonitoring();
                                            } else {
                                              showBackgroundLocationDisclosure(
                                                  context);
                                            }
                                          }
                                        : null,
                                  ),
                                  // ヒントは円内に描画するため外側には出さない
                                  // GeoJSONファイル状態は円の上へ移動済み
                                  const SizedBox(height: 12),
                                  _BottomActions(
                                    isWaitStart: snapshot.status ==
                                        LocationStateStatus.waitStart,
                                    geoJsonReady: controller.geoJsonLoaded,
                                    onLoadFile: () {
                                      _showLoadFileSheet(context, controller);
                                    },
                                    onOpenQr: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const QrScannerPage()),
                                      );
                                    },
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
                                    const SizedBox(height: 16),
                                    _AlarmSnoozeAction(
                                      isSnoozed: controller.isAlarmSnoozed,
                                      onPressed: controller.canSnoozeAlarm
                                          ? controller.snoozeAlarmForOneMinute
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _CreditFooter(),
                      ],
                    ),
            ),
          ),
          // 下部ナビは使用せず、円直下にボタンを配置する構成へ
        );
      },
    );
  }
}

Future<void> _showLoadFileSheet(
  BuildContext context,
  AppController controller,
) async {
  final action = await showModalBottomSheet<_LoadFileAction>(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.map),
              title: const Text('GeoJSONファイルを読み込む'),
              onTap: () {
                Navigator.of(context).pop(_LoadFileAction.geoJson);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_search),
              title: const Text('QRコード画像を読み込む'),
              onTap: () {
                Navigator.of(context).pop(_LoadFileAction.qrImage);
              },
            ),
          ],
        ),
      );
    },
  );

  switch (action) {
    case _LoadFileAction.geoJson:
      await controller.reloadGeoJsonFromPicker();
      return;
    case _LoadFileAction.qrImage:
      await controller.reloadGeoJsonFromQrImagePicker();
      return;
    case null:
      return;
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

class _FileNameInfo extends StatelessWidget {
  const _FileNameInfo({required this.fileName, required this.loaded});

  final String? fileName;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final displayName = loaded ? (fileName ?? '-') : '-';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.map, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'ファイル名: $displayName',
            style: TextStyle(fontSize: 13, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.isWaitStart,
    required this.geoJsonReady,
    required this.onLoadFile,
    required this.onOpenQr,
  });

  final bool isWaitStart;
  final bool geoJsonReady;
  final VoidCallback onLoadFile;
  final VoidCallback onOpenQr;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 中央円タップで開始に統一（ボタンは出さない）
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onLoadFile,
                icon: const Icon(Icons.folder_open),
                label: const Text(
                  'ファイルを\n読み込む',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onOpenQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text(
                  'QRコードを\n読み込む',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CreditFooter extends StatelessWidget {
  const _CreditFooter();

  Future<void> _openContact(BuildContext context) async {
    final launched = await openContactEmail();
    if (!context.mounted || launched) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('メールアプリを開けませんでした。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final footerStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final linkStyle = footerStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Created by Kaito YAMADA',
          textAlign: TextAlign.center,
          style: footerStyle,
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _openContact(context),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              'お問い合わせ: $contactEmail',
              textAlign: TextAlign.center,
              style: linkStyle,
            ),
          ),
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
        PopupMenuItem(value: 1, child: Text('設定')),
        PopupMenuItem(value: 2, child: Text('QRコードを生成')),
      ],
      onSelected: (value) {
        if (value == 1) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          );
        } else if (value == 2) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const QrGeneratorPage()),
          );
        }
      },
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
            if (onTap != null && status == LocationStateStatus.waitStart) ...[
              SizedBox(height: circleSize * 0.04),
              Container(
                padding: EdgeInsets.symmetric(
                  vertical: circleSize * 0.02,
                  horizontal: circleSize * 0.05,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(circleSize * 0.07),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_rounded,
                        size: circleSize * 0.07, color: color),
                    SizedBox(width: circleSize * 0.015),
                    Text(
                      'タップで開始',
                      style: TextStyle(
                        fontSize: circleSize * 0.085,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

class _AlarmSnoozeAction extends StatelessWidget {
  const _AlarmSnoozeAction({
    required this.isSnoozed,
    required this.onPressed,
  });

  final bool isSnoozed;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(isSnoozed ? Icons.volume_off : Icons.snooze),
        label: Text(isSnoozed ? '1分間ミュート中' : '1分間音を停止する'),
      ),
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
