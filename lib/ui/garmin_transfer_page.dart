import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../garmin/garmin_course_encoder.dart';
import '../garmin/garmin_course_selection.dart';
import '../platform/garmin_transfer_client.dart';
import 'qr_scanner_page.dart';

const _garminAccent = Color(0xFF1769C8);
const _garminNavy = Color(0xFF122D55);
const _garminText = Color(0xFF18243A);
const _garminMuted = Color(0xFF526070);
const _garminSelectedSurface = Color(0xFFEAF3FF);
const _garminNeutralSurface = Color(0xFFF7F8FA);

class GarminTransferPage extends StatefulWidget {
  const GarminTransferPage(
      {super.key, this.client = const GarminTransferClient()});
  final GarminTransferClient client;

  @override
  State<GarminTransferPage> createState() => _GarminTransferPageState();
}

class _GarminTransferPageState extends State<GarminTransferPage>
    with WidgetsBindingObserver {
  static const _unsupportedMessage = 'この端末ではGARMINへの送信を利用できません。';
  List<GarminDevice> _devices = const [];
  GarminDevice? _selected;
  String? _selectedDeviceId;
  bool _loadingDevices = false;
  bool _sending = false;
  bool _resetting = false;
  bool _resetCompleted = false;
  bool _waitingForAck = false;
  String? _error;
  String? _notificationWarning;
  GarminTransferResult? _result;
  GarminCourseSelection? _course;
  bool _courseInitialized = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_courseInitialized) return;
    _courseInitialized = true;
    final controller = context.read<AppController>();
    if (controller.geoJsonLoaded) {
      _course = GarminCourseSelection(
        model: controller.geoModel,
        fileName: controller.geoJsonFileName ?? 'argus.geojson',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.client.setDeviceChangeHandler(() {
      if (mounted && !_sending) _refreshDevices();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshDevices());
  }

  @override
  void dispose() {
    widget.client.setDeviceChangeHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDevices();
  }

  Future<void> _selectDevices() async {
    try {
      await widget.client.selectDevices();
      if (mounted) await _refreshDevices();
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? 'GARMINの選択画面を開けませんでした。');
      }
    } on MissingPluginException {
      if (mounted) setState(() => _error = _unsupportedMessage);
    }
  }

  void _chooseDevice(String id) {
    setState(() {
      _selectedDeviceId = id;
      _selected = _devices.where((device) => device.id == id).firstOrNull;
    });
  }

  Future<void> _refreshDevices() async {
    setState(() {
      _loadingDevices = true;
      _error = null;
    });
    try {
      final devices =
          await widget.client.getDevices().timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _devices = devices;
        // Never silently switch to a different watch after a selection is lost.
        _selected = _selectedDeviceId == null
            ? devices.where((d) => d.connected).firstOrNull
            : devices.where((d) => d.id == _selectedDeviceId).firstOrNull;
        _selectedDeviceId ??= _selected?.id;
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'GARMINを検索できませんでした。');
    } on TimeoutException {
      if (mounted) setState(() => _error = 'GARMINの検索がタイムアウトしました。再検索してください。');
    } on MissingPluginException {
      if (mounted) setState(() => _error = _unsupportedMessage);
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  Future<void> _loadFile() async {
    try {
      final file =
          await context.read<AppController>().fileManager.pickGeoJsonFile();
      if (file == null) return;
      final course = await GarminCourseSelection.fromFile(file);
      if (!mounted) return;
      setState(() {
        _course = course;
        _result = null;
        _error = null;
        _resetCompleted = false;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('cancel') ||
          message.contains('user') ||
          message.contains('abort')) {
        return;
      }
      if (mounted) setState(() => _error = 'GeoJSONを読み込めませんでした: $e');
    }
  }

  Future<void> _scanQr() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QrScannerPage(onQrScanned: (qrText) async {
        final course = await GarminCourseSelection.fromQrText(qrText);
        if (!mounted) return;
        setState(() {
          _course = course;
          _result = null;
          _error = null;
          _resetCompleted = false;
        });
      }),
    ));
  }

  Future<void> _send() async {
    final controller = context.read<AppController>();
    final device = _selected;
    final course = _course;
    if (_sending || course == null || device == null) return;
    if (controller.isMonitoring &&
        !course.hasSameGeometry(controller.geoModel)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('スマホと異なる範囲を送りますか？'),
          content: const Text('スマホは現在の範囲の監視を続けます。GARMINには選択した別の範囲を送信します。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('キャンセル')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('GARMINへ送信')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _notificationWarning = null;
      _result = null;
      _resetCompleted = false;
    });
    try {
      if (!controller.monitoringPermissionState.notificationGranted) {
        try {
          await controller.requestNotificationPermission();
        } catch (_) {
          // Notification setup must not prevent a course transfer.
        }
      }
      final payload = GarminCourseEncoder().encode(
        course.model,
        fileName: course.fileName,
      );
      if (mounted) setState(() => _waitingForAck = true);
      final result = await widget.client.sendCourse(device, payload);
      if (mounted) {
        setState(() {
          _waitingForAck = false;
          _result = result;
        });
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      }
      if (controller.monitoringPermissionState.notificationGranted) {
        try {
          await controller.notifier.notifyGarminTransferComplete(
            deviceName: result.deviceName,
            fileName: payload.displayName,
          );
        } catch (_) {
          if (mounted) {
            setState(
                () => _notificationWarning = '転送は完了しましたが、スマホ通知を表示できませんでした。');
          }
        }
      } else if (mounted) {
        setState(() => _notificationWarning = '通知権限がないため、スマホの送信完了通知は表示されません。');
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'GARMINへの転送に失敗しました。');
    } on MissingPluginException {
      if (mounted) setState(() => _error = _unsupportedMessage);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _waitingForAck = false;
        });
      }
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GARMINの監視を停止しますか？'),
        content: const Text('RUN中でも境界の警告を停止します。再開するには範囲を再送信してください。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('監視を停止')),
        ],
      ),
    );
    if (confirmed == true && mounted) await _reset();
  }

  Future<void> _reset() async {
    final device = _selected;
    if (device == null || !device.connected) return;
    setState(() {
      _sending = true;
      _resetting = true;
      _waitingForAck = true;
      _resetCompleted = false;
      _result = null;
      _error = null;
      _notificationWarning = null;
    });
    try {
      await widget.client.resetMonitoring(device);
      if (mounted) {
        setState(() => _resetCompleted = true);
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? 'GARMINの監視を停止できませんでした。');
      }
    } on MissingPluginException {
      if (mounted) setState(() => _error = _unsupportedMessage);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _resetting = false;
          _waitingForAck = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Scaffold(
      appBar: AppBar(
        title: _result == null ? null : const Text('GARMINに送る'),
        toolbarHeight: 52,
        backgroundColor: surface,
        foregroundColor: _garminNavy,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      backgroundColor: surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: _result == null
              ? _buildTransferForm(context)
              : _buildSuccess(context),
        ),
      ),
    );
  }

  Widget _buildTransferForm(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'GARMINに送る',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: _garminNavy,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '選択した境界データをGARMINに送信します。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _garminMuted,
            fontWeight: FontWeight.w400,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        if (_resetCompleted) ...[
          _messagePanel(
            context,
            icon: Icons.notifications_off_outlined,
            title: 'GARMINの監視を停止しました',
            detail: '範囲ファイルは期限まで保持されます。再開には再送信してください。',
          ),
          const SizedBox(height: 16),
        ],
        _courseCard(context),
        const SizedBox(height: 12),
        _watchCard(context),
        if (_waitingForAck) ...[
          const SizedBox(height: 14),
          _panel(
            color: _garminSelectedSurface,
            child: Row(children: [
              const CircularProgressIndicator(key: Key('garmin-ack-progress')),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GARMINのACKを待機中',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: _garminText)),
                    const SizedBox(height: 4),
                    Text(
                        _resetting
                            ? '監視停止の確認中です。通信開始から最大60秒待ちます。'
                            : '保存・照合の確認中です。通信開始から最大60秒待ちます。',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: _garminMuted, fontWeight: FontWeight.w400)),
                  ],
                ),
              ),
            ]),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          _messagePanel(context,
              icon: Icons.error_outline,
              title: '操作を完了できませんでした',
              detail: _error!,
              color: colors.error,
              backgroundColor: const Color(0xFFFFF0F0)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            style: _primaryButtonStyle(),
            onPressed:
                _sending || _course == null || _selected?.connected != true
                    ? null
                    : _send,
            icon: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.watch_outlined),
            label: Text(_sending
                ? (_resetting ? '監視停止ACKを待っています…' : '保存・照合ACKを待っています…')
                : 'GARMINに送信'),
          ),
        ),
        const SizedBox(height: 8),
        Text('保存・照合の確認後に完了します。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: _garminMuted, fontWeight: FontWeight.w400)),
        const SizedBox(height: 22),
        _setupHelp(),
        const SizedBox(height: 20),
        const Divider(),
        _resetAction(context),
      ],
    );
  }

  Widget _courseCard(BuildContext context) {
    final theme = Theme.of(context);
    final course = _course;
    return _panel(
      color: _garminSelectedSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                course == null
                    ? Icons.radio_button_unchecked
                    : Icons.check_circle,
                size: 28,
                color: _garminAccent,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('境界データ',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: _garminText)),
                    const SizedBox(height: 2),
                    Tooltip(
                      message: course?.fileName ?? '未選択',
                      child: Text(
                        course?.fileName ?? '未選択',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: _garminNavy,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      course == null
                          ? '送信する範囲を選択してください。'
                          : '境界データの読み込みが完了しました。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _garminMuted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.description_outlined,
                  label: 'ファイルを選ぶ',
                  onPressed: _sending ? null : _loadFile,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  icon: Icons.qr_code_scanner,
                  label: 'QRで復元',
                  onPressed: _sending ? null : _scanQr,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _watchCard(BuildContext context) {
    final theme = Theme.of(context);
    final watch = _selected;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final watchDetail = _loadingDevices
        ? '時計を探しています…'
        : watch == null
            ? _selectedDeviceId == null
                ? isIos
                    ? 'Garmin ConnectでARGUSに時計を共有してください。'
                    : '接続済みのGARMINが見つかりません。Garmin Connectを確認してください。'
                : '選択したGARMINが見つかりません。送信先を選び直してください。'
            : watch.connected
                ? '接続済み'
                : '未接続';
    return _panel(
      color: _garminNeutralSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_loadingDevices)
                const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.watch_outlined, size: 30, color: _garminNavy),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('送信先GARMIN',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: _garminText)),
                    const SizedBox(height: 2),
                    Text(
                      watch?.name ?? '時計を選択してください',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: _garminNavy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      watchDetail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _garminMuted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: isIos
                    ? _actionButton(
                        icon: Icons.watch_outlined,
                        label: '時計を変更',
                        onPressed: _sending ? null : _selectDevices,
                      )
                    : PopupMenuButton<String>(
                        enabled: !_sending && _devices.isNotEmpty,
                        tooltip: '送信先GARMINを選択',
                        onSelected: _chooseDevice,
                        itemBuilder: (context) => _devices
                            .map((device) => PopupMenuItem<String>(
                                  value: device.id,
                                  child: Text(
                                      '${device.name} · ${device.connected ? '接続済み' : '未接続'}'),
                                ))
                            .toList(),
                        child: _actionSurface(
                          Icons.watch_outlined,
                          '時計を変更',
                          enabled: !_sending && _devices.isNotEmpty,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  icon: Icons.refresh,
                  label: '再検索',
                  onPressed:
                      _loadingDevices || _sending ? null : _refreshDevices,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: TextButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: _garminAccent,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _actionSurface(IconData icon, String label, {required bool enabled}) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: enabled ? _garminAccent : _garminMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: enabled ? _garminAccent : _garminMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF18834D), size: 72),
        const SizedBox(height: 12),
        Text('GARMINへ転送しました',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(color: _garminNavy)),
        const SizedBox(height: 6),
        Text('保存・照合済み · ACK受信',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF18834D), fontWeight: FontWeight.w400)),
        const SizedBox(height: 24),
        _panel(
          color: _garminSelectedSurface,
          child: Column(
            children: [
              _summaryRow('送信先', _result!.deviceName),
              const Divider(height: 24),
              _summaryRow('境界データ', _course?.fileName ?? 'GeoJSON'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _messagePanel(
          context,
          icon: Icons.directions_run,
          title: '時計のRunで監視を確認',
          detail: 'Run中は画面を確認。未開始ならRunを開始してください。',
          color: _garminAccent,
        ),
        if (_notificationWarning != null) ...[
          const SizedBox(height: 16),
          _messagePanel(
            context,
            icon: Icons.info_outline,
            title: 'スマホ通知について',
            detail: _notificationWarning!,
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 56,
          child: FilledButton(
            style: _primaryButtonStyle(),
            onPressed: () => Navigator.pop(context),
            child: const Text('完了'),
          ),
        ),
        const SizedBox(height: 16),
        _resetAction(context),
      ],
    );
  }

  Widget _resetAction(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      TextButton.icon(
        onPressed:
            _sending || _selected?.connected != true ? null : _confirmReset,
        icon: const Icon(Icons.notifications_off_outlined),
        label: const Text('GARMINの監視を停止'),
        style: TextButton.styleFrom(foregroundColor: const Color(0xFF3A6D9E)),
      ),
      Text('RUN中も停止できます。再開するには範囲を再送信してください。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: _garminMuted,
            fontWeight: FontWeight.w400,
          )),
    ]);
  }

  Widget _setupHelp() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE1E8F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        title: const Text('初めてGARMINで使う場合'),
        leading: const Icon(Icons.help_outline),
        textColor: _garminText,
        iconColor: _garminMuted,
        collapsedIconColor: _garminMuted,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            '時計にARGUS Data Fieldをインストールし、Runのデータ画面へ1項目で追加して一度表示してください。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _garminMuted,
                  fontWeight: FontWeight.w400,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '対象: Forerunner 55・165・255・265・945 LTE・955・965、fēnix 6・7・8',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _garminMuted,
                  fontWeight: FontWeight.w400,
                ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    final theme = Theme.of(context);
    return Row(children: [
      SizedBox(
        width: 82,
        child: Text(label,
            style: theme.textTheme.bodyMedium?.copyWith(color: _garminText)),
      ),
      Expanded(
        child: Text(value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: _garminNavy)),
      ),
    ]);
  }

  Widget _messagePanel(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String detail,
    Color color = const Color(0xFF3A587C),
    Color backgroundColor = _garminNeutralSurface,
  }) {
    final theme = Theme.of(context);
    return _panel(
      color: backgroundColor,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: _garminText)),
              const SizedBox(height: 4),
              Text(detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _garminMuted,
                    fontWeight: FontWeight.w400,
                  )),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry? padding,
    Color color = _garminNeutralSurface,
  }) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  ButtonStyle _primaryButtonStyle() => FilledButton.styleFrom(
        backgroundColor: _garminAccent,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
