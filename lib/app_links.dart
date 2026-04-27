import 'package:url_launcher/url_launcher.dart';

const String privacyPolicyUrl =
    'https://github.com/nanigasi-san/Argus/blob/main/privacy.md';
const String contactEmail = 'yamada.orien@gmail.com';

Future<bool> openPrivacyPolicy() {
  return launchUrl(
    Uri.parse(privacyPolicyUrl),
    mode: LaunchMode.externalApplication,
  );
}

Future<bool> openContactEmail() {
  return launchUrl(
    Uri(
      scheme: 'mailto',
      path: contactEmail,
    ),
    mode: LaunchMode.externalApplication,
  );
}
