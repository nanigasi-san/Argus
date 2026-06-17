import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:upgrader/upgrader.dart';

import 'app_controller.dart';
import 'theme/app_theme.dart';
import 'ui/home_page.dart';

// coverage:ignore-start
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await AppController.bootstrap();
  runApp(
    ArgusApp(
      controller: controller,
      upgrader: Upgrader(
        countryCode: 'JP',
        languageCode: 'ja',
      ),
    ),
  );
}
// coverage:ignore-end

class ArgusApp extends StatefulWidget {
  const ArgusApp({
    super.key,
    required this.controller,
    this.upgrader,
  });

  final AppController controller;
  final Upgrader? upgrader;

  @override
  State<ArgusApp> createState() => _ArgusAppState();
}

class _ArgusAppState extends State<ArgusApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      widget.controller.refreshMonitoringPermissionState();
    } else if (state == AppLifecycleState.detached) {
      // タスク終了時は監視と警報を停止する
      unawaited(widget.controller.handleAppTermination());
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = widget.upgrader == null
        ? const HomePage()
        : UpgradeAlert(
            upgrader: widget.upgrader!,
            showIgnore: false,
            showReleaseNotes: false,
            child: const HomePage(),
          );
    return ChangeNotifierProvider.value(
      value: widget.controller,
      child: MaterialApp(
        title: 'Argus',
        theme: AppTheme.light(),
        home: home,
      ),
    );
  }
}
