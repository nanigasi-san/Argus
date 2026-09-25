import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../garmin/garmin_course_encoder.dart';
import '../platform/garmin_transfer_client.dart';
import 'qr_scanner_page.dart';

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
  bool _loadingDevices = false;
  bool _sending = false;
  String? _error;
  String? _notificationWarning;
  GarminTransferResult? _result;

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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDevices();
  }

  Future<void> _selectDevices() async {
    try {
      await widget.client.selectDevices();
    } on PlatformException catch (e) {
      if (mounted)
        setState(() => _error = e.message ?? 'GARMINの選択画面を開けませんでした。');
    } on MissingPluginException {
      if (mounted) setState(() => _error = _unsupportedMessage);
    }
  }

  Future<void> _refreshDevices() async {
    setState(() {
      _loadingDevices = true;
      _error = null;
    });
    try {
      final devices = await widget.client.getDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _selected = devices.where((d) => d.connected).firstOrNull;
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'GARMINを検索できませんでした。');
    } on MissingPluginException {
      if (mounted) setState(() => _error = _unsupportedMessage);
    } finally {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  Future<void> _loadFile() async {
    await context.read<AppController>().reloadGeoJsonFromPicker();
    if (mounted) {
      setState(() {
        _result = null;
        _error = null;
      });
    }
  }

  Future<void> _scanQr() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const QrScannerPage()));
    if (mounted) {
      setState(() {
        _result = null;
        _error = null;
      });
    }
  }

  Future<void> _send() async {
    final controller = context.read<AppController>();
    final device = _selected;
    if (!controller.geoJsonLoaded || device == null) return;
    setState(() {
      _sending = true;
      _error = null;
      _notificationWarning = null;
      _result = null;
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
        controller.geoModel,
        fileName: controller.geoJsonFileName ?? 'argus.geojson',
      );
      final result = await widget.client.sendCourse(device, payload);
      if (mounted) setState(() => _result = result);
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
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('GARMINに送る')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_result != null) ...[
            const Icon(Icons.check_circle, color: Colors.green, size: 88),
            const SizedBox(height: 12),
            const Text('GARMINへ転送しました',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
                '${_result!.deviceName}\n${controller.geoJsonFileName ?? 'GeoJSON'}\n保存・照合済み / ACK受信\n${_result!.elapsedMs} ms',
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完了')),
            const SizedBox(height: 8),
            const Text(
                'GARMINのRun中はData Fieldに受信結果が短く表示されます。Run外では次回開いたときにファイル名を確認してください。',
                textAlign: TextAlign.center),
            if (_notificationWarning != null) ...[
              const SizedBox(height: 12),
              Text(_notificationWarning!, textAlign: TextAlign.center),
            ],
          ] else ...[
            const Text('送信する境界データを選択してください。'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                onPressed: _sending ? null : _loadFile,
                icon: const Icon(Icons.description_outlined),
                label: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('GeoJSONファイルを読み込む'))),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: _sending ? null : _scanQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Padding(
                    padding: EdgeInsets.all(14), child: Text('QRコードから復元'))),
            if (controller.geoJsonLoaded) ...[
              const SizedBox(height: 20),
              Card(
                  child: ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('境界データを読み込みました'),
                subtitle: Text(controller.geoJsonFileName ?? 'GeoJSON'),
              )),
              const SizedBox(height: 12),
              Row(children: [
                const Expanded(
                    child: Text('送信先GARMIN',
                        style: TextStyle(fontWeight: FontWeight.bold))),
                TextButton(
                    onPressed:
                        _loadingDevices || _sending ? null : _refreshDevices,
                    child: const Text('再検索')),
              ]),
              if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                const Text('初回はGarmin Connectで、ARGUSに共有する時計を選んでください。'),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _sending ? null : _selectDevices,
                  child: const Text('Garmin Connectで時計を選ぶ'),
                ),
                const SizedBox(height: 8),
              ],
              if (_loadingDevices)
                const Center(child: CircularProgressIndicator())
              else if (_devices.isEmpty)
                Text(defaultTargetPlatform == TargetPlatform.iOS
                    ? '共有されたGARMINがありません。Garmin Connectで時計を選んでください。'
                    : '接続済みのGARMINが見つかりません。Garmin Connectを確認してください。')
              else
                DropdownButtonFormField<GarminDevice>(
                  initialValue: _selected,
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                  items: _devices
                      .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                              '${d.name}${d.connected ? ' · 接続済み' : ' · 未接続'}')))
                      .toList(),
                  onChanged: _sending
                      ? null
                      : (value) => setState(() => _selected = value),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed:
                    _sending || _selected?.connected != true ? null : _send,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.watch_outlined),
                label: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(_sending ? '保存・照合ACKを待っています…' : 'GARMINに送信')),
              ),
              const SizedBox(height: 8),
              const Text('Runを開始する前に転送してください。ACK受信後にのみ完了します。',
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                  '初回は時計にARGUS Data Fieldをインストールし、Runのデータ画面へ追加して一度表示してください。',
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                  '対象: Forerunner 55・165・255・265・945 LTE・955・965、fēnix 6・7・8',
                  textAlign: TextAlign.center),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
