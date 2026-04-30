import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../app_links.dart';

class BackgroundLocationDisclosurePage extends StatefulWidget {
  const BackgroundLocationDisclosurePage({super.key});

  static const routeTitle = 'バックグラウンド位置情報の開示';

  @override
  State<BackgroundLocationDisclosurePage> createState() =>
      _BackgroundLocationDisclosurePageState();
}

Future<bool?> showBackgroundLocationDisclosure(BuildContext context) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => const BackgroundLocationDisclosurePage(),
    ),
  );
}

class _BackgroundLocationDisclosurePageState
    extends State<BackgroundLocationDisclosurePage> {
  bool _isSubmitting = false;

  Future<void> _handleContinue(AppController controller) async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await controller.completeMonitoringPermissionSetup();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final launched = await openPrivacyPolicy();
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('プライバシーポリシーを開けませんでした。'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Consumer<AppController>(
      builder: (context, controller, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text(BackgroundLocationDisclosurePage.routeTitle),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 44,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '監視機能を使う前にご確認ください',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'ARGUS はジオフェンス監視機能のために位置情報を使用します。',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '監視開始後は、アプリを閉じているときや使用していないときも位置情報を使って競技エリアからの離脱を検知し、通知します。',
                            style: theme.textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'この権限が必要な理由',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                    '・位置情報は GeoJSON で設定した競技エリアの離脱検知に使います。'),
                                const SizedBox(height: 6),
                                const Text(
                                    '・位置情報はアプリを閉じているときや使用していないときも使われます。'),
                                const SizedBox(height: 6),
                                const Text(
                                    '・位置情報データは端末内でのみ処理し、開発者のサーバーへ送信しません。'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () => _openPrivacyPolicy(context),
                            icon: const Icon(Icons.privacy_tip_outlined),
                            label: const Text('プライバシーポリシーを開く'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => _handleContinue(controller),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('同意して位置情報の設定へ進む'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('今はしない'),
                    ),
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
