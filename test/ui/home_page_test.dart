import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:argus/app_controller.dart';
import 'package:argus/state_machine/state.dart';
import 'package:argus/ui/home_page.dart';

import '../support/test_doubles.dart';

Future<void> _pumpHome(
  WidgetTester tester,
  AppController controller,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: const MaterialApp(home: HomePage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hides navigation details when not developer and not outer',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.utc(2024, 1, 1),
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.textContaining('境界までの距離'), findsNothing);
  });

  testWidgets('shows navigation details in developer mode', (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      developerMode: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.inner,
        timestamp: DateTime.utc(2024, 1, 1),
        distanceToBoundaryM: 12.3,
        bearingToBoundaryDeg: 45,
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.textContaining('境界までの距離'), findsOneWidget);
    expect(find.textContaining('方角'), findsOneWidget);
  });

  testWidgets('shows navigation details when state is OUTER', (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.outer,
        timestamp: DateTime.utc(2024, 1, 1),
        distanceToBoundaryM: 5,
        bearingToBoundaryDeg: 180,
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.textContaining('境界までの距離'), findsOneWidget);
    expect(find.textContaining('方角'), findsOneWidget);
  });

  testWidgets('shows GeoJSON chip with file name after loading via picker',
      (tester) async {
    final controller = buildTestController(hasGeoJson: false);
    await _pumpHome(tester, controller);

    // 初期は未ロードでInfo系Chipが出る想定
    expect(find.text('Please select GeoJSON file'), findsOneWidget);

    // 画像のFakeFileManagerは test_square.geojson を返す
    await controller.reloadGeoJsonFromPicker();
    await tester.pumpAndSettle();

    // ファイル未選択メッセージが消え、Chipが表示されることを確認
    expect(find.text('Please select GeoJSON file'), findsNothing);
    expect(find.byType(Chip), findsWidgets);
  });

  testWidgets('bottom actions are visible: Start/Load GeoJSON/Read QR code',
      (tester) async {
    final controller = buildTestController(
      hasGeoJson: true,
      snapshot: StateSnapshot(
        status: LocationStateStatus.waitStart,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        geoJsonLoaded: true,
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.text('Start monitoring'), findsWidgets);
    expect(find.text('Load GeoJSON'), findsOneWidget);
    expect(find.text('Read QR code'), findsOneWidget);
  });
}
