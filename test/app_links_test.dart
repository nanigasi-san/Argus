import 'package:flutter_test/flutter_test.dart';

import 'package:argus/app_links.dart';

import 'support/platform_mocks.dart';

void main() {
  tearDown(() async {
    await clearUrlLauncherMock();
  });

  test('openPrivacyPolicy launches external privacy policy URL', () async {
    final calls = await mockUrlLauncher(launchResult: true);

    final launched = await openPrivacyPolicy();

    expect(launched, isTrue);
    expect(calls, isNotEmpty);
    expect(
      calls.any((call) =>
          call.method.toLowerCase().contains('launch') &&
          call.arguments.toString().contains(privacyPolicyUrl)),
      isTrue,
    );
  });
}
