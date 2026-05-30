import 'package:url_launcher/url_launcher.dart';

const String privacyPolicyUrl =
    'https://argus-lp.vercel.app/privacy.html';
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
