import 'package:firebase_app_check/firebase_app_check.dart';

const circumWebRecaptchaEnterpriseSiteKey =
    String.fromEnvironment('PUBLIC_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY');

class CircumAppCheckStartup {
  const CircumAppCheckStartup._({
    required this.enabled,
    required this.blockStartup,
    required this.message,
  });

  const CircumAppCheckStartup.enabled()
      : this._(
          enabled: true,
          blockStartup: false,
          message: '',
        );

  const CircumAppCheckStartup.blocked(String message)
      : this._(
          enabled: false,
          blockStartup: true,
          message: message,
        );

  final bool enabled;
  final bool blockStartup;
  final String message;
}

ReCaptchaEnterpriseProvider? circumWebAppCheckProvider(String siteKey) {
  final trimmed = siteKey.trim();
  if (trimmed.isEmpty) return null;
  return ReCaptchaEnterpriseProvider(trimmed);
}

Future<CircumAppCheckStartup> initializeCircumAppCheck({
  FirebaseAppCheck? appCheck,
  String webSiteKey = circumWebRecaptchaEnterpriseSiteKey,
}) async {
  final webProvider = circumWebAppCheckProvider(webSiteKey);

  if (webProvider == null) {
    return const CircumAppCheckStartup.blocked(
      'Circum security verification is not configured for this version.',
    );
  }

  try {
    await (appCheck ?? FirebaseAppCheck.instance).activate(
      webProvider: webProvider,
    );
    return const CircumAppCheckStartup.enabled();
  } catch (_) {
    return const CircumAppCheckStartup.blocked(
      'Circum security verification could not start. Please try again.',
    );
  }
}
