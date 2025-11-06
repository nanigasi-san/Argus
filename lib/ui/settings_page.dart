import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../io/config.dart';

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

  Future<void> _initializeControllers() async {
    // デフォルト値を読み込む
    try {
      _defaultConfig = await AppConfig.loadDefault();
    } catch (_) {
      _defaultConfig = AppConfig(
        innerBufferM: 30.0,
        leaveConfirmSamples: 3,
        leaveConfirmSeconds: 10,
        gpsAccuracyBadMeters: 40.0,
        sampleIntervalS: const {'fast': 3},
        sampleDistanceM: const {'fast': 15},
        screenWakeOnLeave: false,
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
    } else {
      // フォールバック
      _innerBufferController.text = '30.0';
      _pollingIntervalController.text = '3';
      _gpsAccuracyThresholdController.text = '40.0';
      _leaveConfirmSamplesController.text = '3';
      _leaveConfirmSecondsController.text = '10';
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

      // 空欄の場合はデフォルト値を使用
      final innerBuffer = _innerBufferController.text.trim().isEmpty
          ? (_defaultConfig?.innerBufferM ?? 30.0)
          : double.parse(_innerBufferController.text);

      final pollingInterval = _pollingIntervalController.text.trim().isEmpty
          ? (_defaultConfig?.sampleIntervalS['fast'] ?? 3)
          : int.parse(_pollingIntervalController.text);

      final gpsAccuracy = _gpsAccuracyThresholdController.text.trim().isEmpty
          ? (_defaultConfig?.gpsAccuracyBadMeters ?? 40.0)
          : double.parse(_gpsAccuracyThresholdController.text);

      final leaveSamples = _leaveConfirmSamplesController.text.trim().isEmpty
          ? (_defaultConfig?.leaveConfirmSamples ?? 3)
          : int.parse(_leaveConfirmSamplesController.text);

      final leaveSeconds = _leaveConfirmSecondsController.text.trim().isEmpty
          ? (_defaultConfig?.leaveConfirmSeconds ?? 10)
          : int.parse(_leaveConfirmSecondsController.text);

      final newConfig = AppConfig(
        innerBufferM: innerBuffer,
        leaveConfirmSamples: leaveSamples,
        leaveConfirmSeconds: leaveSeconds,
        gpsAccuracyBadMeters: gpsAccuracy,
        sampleIntervalS: {
          ...currentConfig.sampleIntervalS,
          'fast': pollingInterval,
        },
        sampleDistanceM: currentConfig.sampleDistanceM,
        screenWakeOnLeave: currentConfig.screenWakeOnLeave,
      );

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
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
          ),
          body: config == null
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextFormField(
                        controller: _innerBufferController,
                        decoration: InputDecoration(
                          labelText: '反応距離 (Inner buffer)',
                          helperText:
                              'エリア境界との距離バッファ（メートル）\nデフォルト: ${_defaultConfig?.innerBufferM.toStringAsFixed(1) ?? '30.0'} m（空欄でデフォルト値を使用）',
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
                          if (num == null || num < 0) {
                            return '0以上の数値を入力してください';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _pollingIntervalController,
                        decoration: InputDecoration(
                          labelText: 'ポーリング間隔 (GPS間隔)',
                          helperText:
                              '位置取得間隔（秒）\nデフォルト: ${_defaultConfig?.sampleIntervalS['fast'] ?? 3} 秒（空欄でデフォルト値を使用）',
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
                          if (num == null || num < 1) {
                            return '1以上の整数を入力してください';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _gpsAccuracyThresholdController,
                        decoration: InputDecoration(
                          labelText: 'GPS精度閾値',
                          helperText:
                              '位置精度がこの値を超えるとGPS不良と判定（メートル）\nデフォルト: ${_defaultConfig?.gpsAccuracyBadMeters.toStringAsFixed(1) ?? '40.0'} m（空欄でデフォルト値を使用）',
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
                          if (num == null || num < 0) {
                            return '0以上の数値を入力してください';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _leaveConfirmSamplesController,
                        decoration: InputDecoration(
                          labelText: '離脱確定サンプル数',
                          helperText:
                              'OUTER確定に必要な連続サンプル数\nデフォルト: ${_defaultConfig?.leaveConfirmSamples ?? 3}（空欄でデフォルト値を使用）',
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
                          if (num == null || num < 1) {
                            return '1以上の整数を入力してください';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _leaveConfirmSecondsController,
                        decoration: InputDecoration(
                          labelText: '離脱確定秒数',
                          helperText:
                              'OUTER確定に必要な経過秒数\nデフォルト: ${_defaultConfig?.leaveConfirmSeconds ?? 10} 秒（空欄でデフォルト値を使用）',
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
                          if (num == null || num < 1) {
                            return '1以上の整数を入力してください';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
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
                        title: const Text('Developer mode'),
                        subtitle: const Text(
                          'Show distance/bearing details even inside the geofence.',
                        ),
                        value: controller.developerMode,
                        onChanged: controller.setDeveloperMode,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          final export = await controller.logger.exportJsonl();
                          if (!context.mounted) return;
                          showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Export (JSONL)'),
                              content: SingleChildScrollView(
                                child: Text(export),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('Export logs'),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
