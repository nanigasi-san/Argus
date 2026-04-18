import 'package:url_launcher/url_launcher.dart';

const String privacyPolicyUrl =
    'https://github.com/nanigasi-san/Argus/blob/main/privacy.md';

Future<bool> openPrivacyPolicy() {
  return launchUrl(
    Uri.parse(privacyPolicyUrl),
    mode: LaunchMode.externalApplication,
  );
}
