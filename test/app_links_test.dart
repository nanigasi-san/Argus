import 'package:flutter_test/flutter_test.dart';

import 'package:argus/app_links.dart';

import 'support/platform_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('privacy policy uses the public non-editable URL', () {
    expect(
      privacyPolicyUrl,
      'https://argus-lp.vercel.app/privacy.html',
    );
  });

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

  test('openContactEmail launches mailto URL', () async {
    final calls = await mockUrlLauncher(launchResult: true);

    final launched = await openContactEmail();

    expect(launched, isTrue);
    expect(calls, isNotEmpty);
    expect(
      calls.any((call) =>
          call.method.toLowerCase().contains('launch') &&
          call.arguments.toString().contains('mailto:$contactEmail')),
      isTrue,
    );
  });
}
