import 'package:flutter/material.dart';

import 'garmin_transfer_page.dart';
import 'home_page.dart';

enum _UsageMode { phone, garmin }

const _modeAccentBlue = Color(0xFF1769C8);

/// The entry screen only selects a destination; monitoring and transfer keep
/// using their existing pages and shared AppController.
class UsageModeSelectionPage extends StatefulWidget {
  const UsageModeSelectionPage({super.key});

  @override
  State<UsageModeSelectionPage> createState() => _UsageModeSelectionPageState();
}

class _UsageModeSelectionPageState extends State<UsageModeSelectionPage> {
  _UsageMode _selectedMode = _UsageMode.phone;

  void _openSelectedMode() {
    final destination = _selectedMode == _UsageMode.phone
        ? const HomePage()
        : const GarminTransferPage();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                    child: Column(
                      children: [
                        Text(
                          'ARGUS',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: const Color(0xFF122D55),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 54),
                        Text(
                          'どちらで利用しますか？',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: const Color(0xFF18243A),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'ご利用のデバイスを選択してください。\n選択後、次の画面に進みます。',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w400,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 34),
                        _ModeChoiceCard(
                          key: const Key('phoneModeChoice'),
                          selected: _selectedMode == _UsageMode.phone,
                          icon: Icons.smartphone_outlined,
                          title: 'スマホで利用',
                          description: 'これまでどおりスマホで\nエリアを監視します。',
                          onTap: () => setState(
                            () => _selectedMode = _UsageMode.phone,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _ModeChoiceCard(
                          key: const Key('garminModeChoice'),
                          selected: _selectedMode == _UsageMode.garmin,
                          icon: Icons.watch_outlined,
                          title: 'GARMINだけで利用\n（試験機能）',
                          description: 'スマホからGARMINへ\n境界データを送信します。',
                          onTap: () => setState(
                            () => _selectedMode = _UsageMode.garmin,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            key: const Key('usageModeNextButton'),
                            onPressed: _openSelectedMode,
                            style: FilledButton.styleFrom(
                              backgroundColor: _modeAccentBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('次へ'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChoiceCard extends StatelessWidget {
  const _ModeChoiceCard({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: title.replaceAll('\n', ''),
      child: Material(
        color: selected ? const Color(0xFFEAF3FF) : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 112),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 23,
                  color: selected
                      ? _modeAccentBlue
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Icon(icon, size: 36, color: const Color(0xFF122D55)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF18243A),
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w400,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
