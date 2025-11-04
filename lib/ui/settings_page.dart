import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppController>(
      builder: (context, controller, _) {
        final config = controller.config;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: config == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      Text('Inner buffer: ${config.innerBufferM} m'),
                      Text(
                        'Leave confirm: '
                        '${config.leaveConfirmSamples} samples / '
                        '${config.leaveConfirmSeconds} s',
                      ),
                      Text(
                        'GPS bad threshold: '
                        '${config.gpsAccuracyBadMeters} m',
                      ),
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
