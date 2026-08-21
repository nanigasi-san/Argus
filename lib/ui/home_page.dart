import 'dart:async';

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
  const HomePage({super.key}); // coverage:ignore-line

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final snapshot = controller.snapshot;
        final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
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

        final permissionCard = controller.shouldShowPermissionSetupCard
            ? MonitoringPermissionCard(
                permissionState: controller.monitoringPermissionState,
                onOpenMonitoringSetup: () async {
                  await showBackgroundLocationDisclosure(context);
                },
                onRequestNotifications:
                    controller.requestNotificationPermission,
                onRefresh: controller.refreshMonitoringPermissionState,
                onOpenSettings: isIOS
                    ? () => _openPermissionSettings(context, controller)
                    : null,
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: _HomeScrollableContent(
                controller: controller,
                snapshot: snapshot,
                permissionCard: permissionCard,
                showNavigationDetails: showNav,
              ),
            ),
          ),
          // 下部ナビは使用せず、円直下にボタンを配置する構成へ
        );
      },
    );
  }
}

Future<void> _openPermissionSettings(
  BuildContext context,
  AppController controller,
) async {
  final opened = await controller.openPermissionSettings();
  if (!context.mounted || opened) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('アプリ設定を開けませんでした。'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class _HomeScrollableContent extends StatelessWidget {
  const _HomeScrollableContent({
    required this.controller,
    required this.snapshot,
    required this.permissionCard,
    required this.showNavigationDetails,
  });

  final AppController controller;
  final StateSnapshot snapshot;
  final Widget? permissionCard;
  final bool showNavigationDetails;

  @override
  Widget build(BuildContext context) {
    final isDeveloperMode = controller.developerMode;
    final isMonitoring = controller.isMonitoringSession;
    final accuracyThreshold = controller.config?.gpsAccuracyBadMeters;
    final usesLastReliableNavigation =
        snapshot.status == LocationStateStatus.outer &&
            (snapshot.horizontalAccuracyM == null ||
                (accuracyThreshold != null &&
                    snapshot.horizontalAccuracyM! > accuracyThreshold));
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  if (permissionCard != null) ...[
                    permissionCard!,
                    const SizedBox(height: 16),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _GpsAccuracyInfo(
                            accuracyM: snapshot.horizontalAccuracyM),
                        const SizedBox(height: 6),
                        _FileNameInfo(
                          fileName: controller.geoJsonFileName,
                          loaded: controller.geoJsonLoaded,
                        ),
                        const SizedBox(height: 20),
                        _LargeStatusDisplay(
                          status: snapshot.status,
                          lifecycle: controller.monitoringLifecycle,
                          onTap: snapshot.status ==
                                      LocationStateStatus.waitStart &&
                                  !isMonitoring
                              ? () {
                                  if (controller.canStartMonitoring) {
                                    unawaited(_startMonitoringAfterAlarmCheck(
                                      context,
                                      controller,
                                    ));
                                  } else {
                                    showBackgroundLocationDisclosure(context);
                                  }
                                }
                              : null,
                        ),
                        const SizedBox(height: 12),
                        if (isMonitoring) ...[
                          const _ForceCloseWarning(),
                          const SizedBox(height: 12),
                        ],
                        if (isMonitoring)
                          _HoldToFinishRaceButton(
                            duration: const Duration(seconds: 5),
                            onCompleted: controller.stopMonitoring,
                          )
                        else
                          _BottomActions(
                            status: snapshot.status,
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
                        if (showNavigationDetails) ...[
                          const SizedBox(height: 24),
                          if (usesLastReliableNavigation) ...[
                            Container(
                              key: const Key('low-accuracy-navigation-warning'),
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'GPS精度が悪いため、最後に精度が良かった位置からの案内を表示しています。現在位置として過信しないでください。',
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
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
                          if (snapshot.status == LocationStateStatus.outer) ...[
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
                  if (isDeveloperMode) ...[
                    const Divider(),
                    const SizedBox(height: 8),
                    _DeveloperDetails(
                      controller: controller,
                      snapshot: snapshot,
                    ),
                  ],
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.only(top: 96),
                    child: _CreditFooter(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _AlarmVolumeDialogAction {
  recheck,
  cancel,
}

Future<void> _startMonitoringAfterAlarmCheck(
  BuildContext context,
  AppController controller,
) async {
  final canStart = await controller.canStartWithCurrentAlarmVolume();
  if (!context.mounted) {
    return;
  }
  if (canStart) {
    await controller.startMonitoring();
    return;
  }

  await _showAlarmVolumeGuidanceDialog(context, controller);
}

Future<void> _showAlarmVolumeGuidanceDialog(
  BuildContext context,
  AppController controller,
) async {
  final action = await showDialog<_AlarmVolumeDialogAction>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('アラーム音量が低すぎます'),
        content: const Text(
          '端末のアラーム音量が５０％未満です。警報音が聞こえない可能性があるため、５０％以上に上げてから開始してください。',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final opened = await controller.openAlarmSoundSettings();
              if (!dialogContext.mounted || opened) {
                return;
              }
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('音設定を開けませんでした。'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('音設定を開く'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(_AlarmVolumeDialogAction.recheck);
            },
            child: const Text('再確認'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(_AlarmVolumeDialogAction.cancel);
            },
            child: const Text('キャンセル'),
          ),
        ],
      );
    },
  );

  if (!context.mounted || action != _AlarmVolumeDialogAction.recheck) {
    return;
  }

  await _startMonitoringAfterAlarmCheck(context, controller);
}

class _DeveloperDetails extends StatelessWidget {
  const _DeveloperDetails({
    required this.controller,
    required this.snapshot,
  });

  final AppController controller;
  final StateSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('現在の状態: ${snapshot.status.name}'),
        if ((snapshot.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('メモ: ${snapshot.notes}'),
        ],
        const SizedBox(height: 16),
        Text('最終更新: ${snapshot.timestamp.toLocal()}'),
        const SizedBox(height: 8),
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
        Text('GeoJSON読込済み: ${controller.geoJsonLoaded}'),
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
          ...controller.logs.take(5).map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _LogCard(entry: entry),
                ),
              ),
        ],
      ],
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
    required this.status,
    required this.onLoadFile,
    required this.onOpenQr,
  });

  final LocationStateStatus status;
  final VoidCallback onLoadFile;
  final VoidCallback onOpenQr;

  bool get _isWaiting =>
      status == LocationStateStatus.waitStart ||
      status == LocationStateStatus.waitGeoJson;

  @override
  Widget build(BuildContext context) {
    if (!_isWaiting) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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

class _ForceCloseWarning extends StatelessWidget {
  const _ForceCloseWarning();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('force-close-warning'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: colors.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '監視中はアプリを強制終了しないでください。画面ロックやホーム画面では監視を続けますが、強制終了すると停止します。',
              style: TextStyle(color: colors.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldToFinishRaceButton extends StatefulWidget {
  const _HoldToFinishRaceButton({
    required this.duration,
    required this.onCompleted,
  });

  final Duration duration;
  final Future<void> Function() onCompleted;

  @override
  State<_HoldToFinishRaceButton> createState() =>
      _HoldToFinishRaceButtonState();
}

class _HoldToFinishRaceButtonState extends State<_HoldToFinishRaceButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _finishTimer;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
  }

  @override
  void didUpdateWidget(covariant _HoldToFinishRaceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // coverage:ignore-start
    // The production button duration is constant; this keeps the state object
    // correct if tests or future callers provide a different duration.
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    // coverage:ignore-end
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startHold() {
    if (_completed) {
      return;
    }
    _finishTimer?.cancel();
    _finishTimer = Timer(widget.duration, () {
      if (_completed) {
        return;
      }
      _completed = true;
      unawaited(widget.onCompleted());
    });
    _controller.forward(from: 0);
  }

  void _cancelHold() {
    if (_completed) {
      return;
    }
    _finishTimer?.cancel();
    _finishTimer = null;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = colorScheme.surfaceContainerHighest;
    final fillColor = Colors.green;
    final textColor = colorScheme.onSurface;
    final radius = BorderRadius.circular(8);

    return Semantics(
      key: const Key('finish-race-button'),
      button: true,
      label: '長押しでレース終了',
      child: Material(
        color: baseColor,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _startHold(),
          onPointerUp: (_) => _cancelHold(),
          onPointerCancel: (_) => _cancelHold(), // coverage:ignore-line
          child: InkWell(
            splashColor: fillColor.withValues(alpha: 0.12),
            highlightColor: fillColor.withValues(alpha: 0.08),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Stack(
                  children: [
                    FractionallySizedBox(
                      key: const Key('finish-race-progress-fill'),
                      widthFactor: _controller.value,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 52,
                        color: fillColor.withValues(alpha: 0.86),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.stop_circle_outlined, color: textColor),
                          const SizedBox(width: 8),
                          Text(
                            '長押しでレース終了',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
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
        const SizedBox(height: 2),
        Text(
          'Special thanks for K.M, R.M',
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

  Future<void> _showQrGenerationNotice(BuildContext context) async {
    final action = await showDialog<_QrGenerationNoticeAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('大会でのご利用について'),
        content: const Text('大会での利用の際はご相談ください。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              _QrGenerationNoticeAction.generate,
            ),
            child: const Text('このまま生成'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              _QrGenerationNoticeAction.contact,
            ),
            child: const Text('お問い合わせ'),
          ),
        ],
      ),
    );

    if (!context.mounted || action == null) {
      return;
    }
    if (action == _QrGenerationNoticeAction.generate) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const QrGeneratorPage()),
      );
      return;
    }

    final launched = await openContactPage();
    if (!context.mounted || launched) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('お問い合わせページを開けませんでした。')),
    );
  }

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
          _showQrGenerationNotice(context);
        }
      },
    );
  }
}

enum _QrGenerationNoticeAction {
  generate,
  contact,
}

class _LargeStatusDisplay extends StatelessWidget {
  const _LargeStatusDisplay({
    required this.status,
    required this.lifecycle,
    this.onTap,
  });

  final LocationStateStatus status;
  final MonitoringLifecycle lifecycle;
  final VoidCallback? onTap;

  bool get _showLifecycle =>
      lifecycle != MonitoringLifecycle.idle &&
      lifecycle != MonitoringLifecycle.active;

  Color _color(LocationStateStatus status) {
    if (_showLifecycle) {
      return switch (lifecycle) {
        MonitoringLifecycle.starting ||
        MonitoringLifecycle.acquiring =>
          Colors.blue,
        MonitoringLifecycle.stale ||
        MonitoringLifecycle.reconnecting =>
          Colors.deepOrange,
        MonitoringLifecycle.stopping => Colors.blueGrey,
        MonitoringLifecycle.failed => Colors.red,
        MonitoringLifecycle.idle || MonitoringLifecycle.active => Colors.blue,
      };
    }
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
    if (_showLifecycle) {
      return switch (lifecycle) {
        MonitoringLifecycle.starting => '開始中',
        MonitoringLifecycle.acquiring => 'GPS取得中',
        MonitoringLifecycle.stale => 'GPS停止',
        MonitoringLifecycle.reconnecting => '再接続中',
        MonitoringLifecycle.stopping => '停止中',
        MonitoringLifecycle.failed => '開始失敗',
        MonitoringLifecycle.idle || MonitoringLifecycle.active => '',
      };
    }
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
    if (_showLifecycle) {
      return switch (lifecycle) {
        MonitoringLifecycle.starting => 'STARTING',
        MonitoringLifecycle.acquiring => 'ACQUIRING GPS',
        MonitoringLifecycle.stale => 'GPS STALE',
        MonitoringLifecycle.reconnecting => 'RECONNECTING',
        MonitoringLifecycle.stopping => 'STOPPING',
        MonitoringLifecycle.failed => 'FAILED',
        MonitoringLifecycle.idle || MonitoringLifecycle.active => '',
      };
    }
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
    '北',
    '北東',
    '東',
    '南東',
    '南',
    '南西',
    '西',
    '北西',
  ];
  final normalized = (bearing % 360 + 360) % 360;
  final index = ((normalized + 22.5) ~/ 45) % labels.length;
  return '${normalized.toStringAsFixed(0)}度 (${labels[index]})';
}

String _formatLatLng(LatLng point) {
  return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
}
