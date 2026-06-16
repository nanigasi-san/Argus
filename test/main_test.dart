import 'package:flutter_test/flutter_test.dart';

import 'package:argus/main.dart';

import 'support/test_doubles.dart';

void main() {
  testWidgets('Argus app displays correctly', (WidgetTester tester) async {
    final controller = buildTestController();

    await tester.pumpWidget(ArgusApp(controller: controller));
    await tester.pump();

    expect(find.text('ARGUS'), findsWidgets);
  });
}
