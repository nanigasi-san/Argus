import 'package:url_launcher/url_launcher.dart';

const String privacyPolicyUrl = 'https://nanigasi-san.github.io/Argus/';

Future<bool> openPrivacyPolicy() {
  return launchUrl(
    Uri.parse(privacyPolicyUrl),
    mode: LaunchMode.externalApplication,
  );
}
