import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../app_links.dart';
import '../io/config.dart';
import 'background_location_disclosure_page.dart';
import 'monitoring_permission_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _innerBufferController;
  late final TextEditingController _pollingIntervalController;
  late final TextEditingController _gpsAccuracyThresholdController;
  late final TextEditingController _leaveConfirmSamplesController;
  late final TextEditingController _leaveConfirmSecondsController;
  double _alarmVolume = 0.5;
  bool _isSaving = false;
  AppConfig? _defaultConfig;

  @override
  void initState() {
    super.initState();
    _innerBufferController = TextEditingController();
    _pollingIntervalController = TextEditingController();
    _gpsAccuracyThresholdController = TextEditingController();
    _leaveConfirmSamplesController = TextEditingController();
    _leaveConfirmSecondsController = TextEditingController();
    _initializeControllers().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _openPrivacyPolicy() async {
    final launched = await openPrivacyPolicy();
    if (!mounted || launched) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('プライバシーポリシーを開けませんでした。'),
      ),
    );
  }

  Future<void> _initializeControllers() async {
    // デフォルト値を読み込む
    try {
      _defaultConfig = await AppConfig.loadDefault();
    } catch (_) {
      _defaultConfig = AppConfig(
        innerBufferM: AppConfig.defaultInnerBufferM,
        leaveConfirmSamples: AppConfig.defaultLeaveConfirmSamples,
        leaveConfirmSeconds: AppConfig.defaultLeaveConfirmSeconds,
        gpsAccuracyBadMeters: AppConfig.defaultGpsAccuracyBadMeters,
        sampleIntervalS: const {
          'fast': AppConfig.defaultFastSampleIntervalS,
        },
        alarmVolume: AppConfig.defaultAlarmVolume,
      );
    }

    if (!mounted) return;
    final controller = Provider.of<AppController>(context, listen: false);
    final config = controller.config;
    if (config != null) {
      _innerBufferController.text = config.innerBufferM.toStringAsFixed(1);
      _pollingIntervalController.text =
          (config.sampleIntervalS['fast'] ?? 3).toString();
      _gpsAccuracyThresholdController.text =
          config.gpsAccuracyBadMeters.toStringAsFixed(1);
      _leaveConfirmSamplesController.text =
          config.leaveConfirmSamples.toString();
      _leaveConfirmSecondsController.text =
          config.leaveConfirmSeconds.toString();
      _alarmVolume = config.alarmVolume;
    } else if (_defaultConfig != null) {
      // デフォルト値で初期化（configがnullの場合）
      _innerBufferController.text =
          _defaultConfig!.innerBufferM.toStringAsFixed(1);
      _pollingIntervalController.text =
          (_defaultConfig!.sampleIntervalS['fast'] ?? 3).toString();
      _gpsAccuracyThresholdController.text =
          _defaultConfig!.gpsAccuracyBadMeters.toStringAsFixed(1);
      _leaveConfirmSamplesController.text =
          _defaultConfig!.leaveConfirmSamples.toString();
      _leaveConfirmSecondsController.text =
          _defaultConfig!.leaveConfirmSeconds.toString();
      _alarmVolume = _defaultConfig!.alarmVolume;
    } else {
      // coverage:ignore-start
      // フォールバック
      _innerBufferController.text =
          AppConfig.defaultInnerBufferM.toStringAsFixed(1);
      _pollingIntervalController.text =
          AppConfig.defaultFastSampleIntervalS.toString();
      _gpsAccuracyThresholdController.text =
          AppConfig.defaultGpsAccuracyBadMeters.toStringAsFixed(1);
      _leaveConfirmSamplesController.text =
          AppConfig.defaultLeaveConfirmSamples.toString();
      _leaveConfirmSecondsController.text =
          AppConfig.defaultLeaveConfirmSeconds.toString();
      // coverage:ignore-end
    }
  }

  @override
  void dispose() {
    _innerBufferController.dispose();
    _pollingIntervalController.dispose();
    _gpsAccuracyThresholdController.dispose();
    _leaveConfirmSamplesController.dispose();
    _leaveConfirmSecondsController.dispose();
    super.dispose();
  }

  Future<void> _applySettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final controller = Provider.of<AppController>(context, listen: false);
      final currentConfig = controller.config;
      if (currentConfig == null) {
        return;
      }

      // デフォルト値を取得（まだ読み込まれていない場合）
      _defaultConfig ??= await AppConfig.loadDefault();

      final innerBuffer = _readDouble(
        _innerBufferController,
        _defaultConfig?.innerBufferM ?? AppConfig.defaultInnerBufferM,
      );
      final pollingInterval = _readInt(
        _pollingIntervalController,
        _defaultConfig?.sampleIntervalS['fast'] ??
            AppConfig.defaultFastSampleIntervalS,
      );
      final gpsAccuracy = _readDouble(
        _gpsAccuracyThresholdController,
        _defaultConfig?.gpsAccuracyBadMeters ??
            AppConfig.defaultGpsAccuracyBadMeters,
      );
      final leaveSamples = _readInt(
        _leaveConfirmSamplesController,
        _defaultConfig?.leaveConfirmSamples ??
            AppConfig.defaultLeaveConfirmSamples,
      );
      final leaveSeconds = _readInt(
        _leaveConfirmSecondsController,
        _defaultConfig?.leaveConfirmSeconds ??
            AppConfig.defaultLeaveConfirmSeconds,
      );

      final newConfig = AppConfig(
        innerBufferM: innerBuffer,
        leaveConfirmSamples: leaveSamples,
        leaveConfirmSeconds: leaveSeconds,
        gpsAccuracyBadMeters: gpsAccuracy,
        sampleIntervalS: {
          ...currentConfig.sampleIntervalS,
          'fast': pollingInterval,
        },
        alarmVolume: _alarmVolume,
      ).normalized();

      await controller.updateConfig(newConfig);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('設定を反映しました'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('設定の反映に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final config = controller.config;
        final viewPadding = MediaQuery.viewPaddingOf(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('設定'),
          ),
          body: config == null
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                        16, 16, 16, 16 + viewPadding.bottom),
                    children: [
                      MonitoringPermissionCard(
                        permissionState: controller.monitoringPermissionState,
                        onOpenMonitoringSetup: () async {
                          await showBackgroundLocationDisclosure(context);
                        },
                        onRequestNotifications:
                            controller.requestNotificationPermission,
                        onRefresh: controller.refreshMonitoringPermissionState,
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        key: const Key('privacyPolicyTile'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('プライバシーポリシー'),
                        subtitle: const Text(
                          '位置情報とカメラの取り扱いを確認できます',
                        ),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: _openPrivacyPolicy,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('innerBufferField'),
                        controller: _innerBufferController,
                        decoration: InputDecoration(
                          labelText: '境界バッファ距離',
                          helperText:
                              '境界からこの距離以内を近接として扱います。範囲: ${AppConfig.minInnerBufferM.toStringAsFixed(0)}-${AppConfig.maxInnerBufferM.toStringAsFixed(0)} m\nデフォルト: ${_defaultConfig?.innerBufferM.toStringAsFixed(1) ?? AppConfig.defaultInnerBufferM.toStringAsFixed(1)} m（空欄でデフォルト値）',
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d*'),
                          ),
                        ],
                        validator: (value) {
                          // 空欄は許可（デフォルト値を使用）
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final num = double.tryParse(value);
                          return _validateDoubleRange(
                            num,
                            AppConfig.minInnerBufferM,
                            AppConfig.maxInnerBufferM,
                            'm',
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('pollingIntervalField'),
                        controller: _pollingIntervalController,
                        decoration: InputDecoration(
                          labelText: 'GPS取得間隔',
                          helperText:
                              '位置情報を継続取得する間隔です。範囲: ${AppConfig.minSampleIntervalS}-${AppConfig.maxSampleIntervalS} 秒\nデフォルト: ${_defaultConfig?.sampleIntervalS['fast'] ?? AppConfig.defaultFastSampleIntervalS} 秒（空欄でデフォルト値）',
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          // 空欄は許可（デフォルト値を使用）
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final num = int.tryParse(value);
                          return _validateIntRange(
                            num,
                            AppConfig.minSampleIntervalS,
                            AppConfig.maxSampleIntervalS,
                            '秒',
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('gpsAccuracyField'),
                        controller: _gpsAccuracyThresholdController,
                        decoration: InputDecoration(
                          labelText: 'GPS精度しきい値',
                          helperText:
                              '推定精度がこの値を超えるとGPS不良として扱います。範囲: ${AppConfig.minGpsAccuracyBadMeters.toStringAsFixed(0)}-${AppConfig.maxGpsAccuracyBadMeters.toStringAsFixed(0)} m\nデフォルト: ${_defaultConfig?.gpsAccuracyBadMeters.toStringAsFixed(1) ?? AppConfig.defaultGpsAccuracyBadMeters.toStringAsFixed(1)} m（空欄でデフォルト値）',
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d*'),
                          ),
                        ],
                        validator: (value) {
                          // 空欄は許可（デフォルト値を使用）
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final num = double.tryParse(value);
                          return _validateDoubleRange(
                            num,
                            AppConfig.minGpsAccuracyBadMeters,
                            AppConfig.maxGpsAccuracyBadMeters,
                            'm',
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('leaveConfirmSamplesField'),
                        controller: _leaveConfirmSamplesController,
                        decoration: InputDecoration(
                          labelText: '離脱確定サンプル数',
                          helperText:
                              'エリア外と確定するために必要な連続判定回数です。範囲: ${AppConfig.minLeaveConfirmSamples}-${AppConfig.maxLeaveConfirmSamples} 回\nデフォルト: ${_defaultConfig?.leaveConfirmSamples ?? AppConfig.defaultLeaveConfirmSamples} 回（空欄でデフォルト値）',
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          // 空欄は許可（デフォルト値を使用）
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final num = int.tryParse(value);
                          return _validateIntRange(
                            num,
                            AppConfig.minLeaveConfirmSamples,
                            AppConfig.maxLeaveConfirmSamples,
                            '回',
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('leaveConfirmSecondsField'),
                        controller: _leaveConfirmSecondsController,
                        decoration: InputDecoration(
                          labelText: '離脱確定秒数',
                          helperText:
                              'エリア外と確定するために必要な経過時間です。範囲: ${AppConfig.minLeaveConfirmSeconds}-${AppConfig.maxLeaveConfirmSeconds} 秒\nデフォルト: ${_defaultConfig?.leaveConfirmSeconds ?? AppConfig.defaultLeaveConfirmSeconds} 秒（空欄でデフォルト値）',
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          // 空欄は許可（デフォルト値を使用）
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final num = int.tryParse(value);
                          return _validateIntRange(
                            num,
                            AppConfig.minLeaveConfirmSeconds,
                            AppConfig.maxLeaveConfirmSeconds,
                            '秒',
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'アラーム音量',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Slider(
                            value: _alarmVolume,
                            min: 0.0,
                            max: 1.0,
                            divisions: 20,
                            label: '${(_alarmVolume * 100).round()}%',
                            onChanged: (value) {
                              setState(() {
                                _alarmVolume = value;
                              });
                            },
                          ),
                          Text(
                            '音量: ${(_alarmVolume * 100).round()}% (デフォルト: 50%)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: const Key('saveSettingsButton'),
                        onPressed: _isSaving ? null : _applySettings,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('設定を反映'),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      SwitchListTile.adaptive(
                        key: const Key('developerModeSwitch'),
                        title: const Text('開発者モード'),
                        subtitle: const Text(
                          'エリア内でも距離や方角などの詳細情報を表示します。',
                        ),
                        value: controller.developerMode,
                        onChanged: controller.setDeveloperMode,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        key: const Key('exportLogsButton'),
                        onPressed: () async {
                          final export = await controller.logger.exportJsonl();
                          if (!context.mounted) return;
                          showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('ログ出力 (JSONL)'),
                              content: SingleChildScrollView(
                                child: Text(export),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('閉じる'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('ログを出力'),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  double _readDouble(TextEditingController controller, double fallback) {
    final text = controller.text.trim();
    return text.isEmpty ? fallback : double.parse(text);
  }

  int _readInt(TextEditingController controller, int fallback) {
    final text = controller.text.trim();
    return text.isEmpty ? fallback : int.parse(text);
  }

  String? _validateDoubleRange(
    double? value,
    double min,
    double max,
    String unit,
  ) {
    if (value == null) {
      return '数値を入力してください';
    }
    if (value < min || value > max) {
      return '${min.toStringAsFixed(0)}-${max.toStringAsFixed(0)} $unit の範囲で入力してください';
    }
    return null;
  }

  String? _validateIntRange(int? value, int min, int max, String unit) {
    if (value == null) {
      return '整数を入力してください';
    }
    if (value < min || value > max) {
      return '$min-$max $unit の範囲で入力してください';
    }
    return null;
  }
}
