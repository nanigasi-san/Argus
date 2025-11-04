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
  late TextEditingController _innerBufferController;
  late TextEditingController _pollingIntervalController;
  late TextEditingController _gpsAccuracyThresholdController;
  late TextEditingController _leaveConfirmSamplesController;
  late TextEditingController _leaveConfirmSecondsController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    final controller = Provider.of<AppController>(context, listen: false);
    final config = controller.config;
    if (config != null) {
      _innerBufferController = TextEditingController(
        text: config.innerBufferM.toStringAsFixed(1),
      );
      _pollingIntervalController = TextEditingController(
        text: (config.sampleIntervalS['fast'] ?? 3).toString(),
      );
      _gpsAccuracyThresholdController = TextEditingController(
        text: config.gpsAccuracyBadMeters.toStringAsFixed(1),
      );
      _leaveConfirmSamplesController = TextEditingController(
        text: config.leaveConfirmSamples.toString(),
      );
      _leaveConfirmSecondsController = TextEditingController(
        text: config.leaveConfirmSeconds.toString(),
      );
    } else {
      // デフォルト値で初期化（configがnullの場合）
      _innerBufferController = TextEditingController(text: '30.0');
      _pollingIntervalController = TextEditingController(text: '3');
      _gpsAccuracyThresholdController = TextEditingController(text: '40.0');
      _leaveConfirmSamplesController = TextEditingController(text: '3');
      _leaveConfirmSecondsController = TextEditingController(text: '10');
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

      final newConfig = AppConfig(
        innerBufferM: double.parse(_innerBufferController.text),
        leaveConfirmSamples: int.parse(_leaveConfirmSamplesController.text),
        leaveConfirmSeconds: int.parse(_leaveConfirmSecondsController.text),
        gpsAccuracyBadMeters:
            double.parse(_gpsAccuracyThresholdController.text),
        sampleIntervalS: {
          ...currentConfig.sampleIntervalS,
          'fast': int.parse(_pollingIntervalController.text),
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
                        decoration: const InputDecoration(
                          labelText: '反応距離 (Inner buffer)',
                          helperText: 'エリア境界との距離バッファ（メートル）',
                          border: OutlineInputBorder(),
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
                          if (value == null || value.isEmpty) {
                            return '値を入力してください';
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
                        decoration: const InputDecoration(
                          labelText: 'ポーリング間隔 (GPS間隔)',
                          helperText: '位置取得間隔（秒）',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '値を入力してください';
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
                        decoration: const InputDecoration(
                          labelText: 'GPS精度閾値',
                          helperText: '位置精度がこの値を超えるとGPS不良と判定（メートル）',
                          border: OutlineInputBorder(),
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
                          if (value == null || value.isEmpty) {
                            return '値を入力してください';
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
                        decoration: const InputDecoration(
                          labelText: '離脱確定サンプル数',
                          helperText: 'OUTER確定に必要な連続サンプル数',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '値を入力してください';
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
                        decoration: const InputDecoration(
                          labelText: '離脱確定秒数',
                          helperText: 'OUTER確定に必要な経過秒数',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '値を入力してください';
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
                          final export =
                              await controller.logger.exportJsonl();
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
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
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
