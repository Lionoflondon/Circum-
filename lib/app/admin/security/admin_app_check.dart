import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

const circumWebRecaptchaEnterpriseSiteKey =
    String.fromEnvironment('CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY');

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

AndroidProvider circumAndroidAppCheckProvider({required bool debug}) {
  return debug ? AndroidProvider.debug : AndroidProvider.playIntegrity;
}

AppleProvider circumAppleAppCheckProvider({required bool debug}) {
  return debug
      ? AppleProvider.debug
      : AppleProvider.appAttestWithDeviceCheckFallback;
}

ReCaptchaEnterpriseProvider? circumWebAppCheckProvider({
  required bool isWeb,
  required String siteKey,
}) {
  if (!isWeb) return null;
  final trimmed = siteKey.trim();
  if (trimmed.isEmpty) return null;
  return ReCaptchaEnterpriseProvider(trimmed);
}

Future<CircumAppCheckStartup> initializeCircumAppCheck({
  FirebaseAppCheck? appCheck,
  bool isWeb = kIsWeb,
  bool debug = kDebugMode,
  String webSiteKey = circumWebRecaptchaEnterpriseSiteKey,
}) async {
  debugPrint(
    'Admin App Check runtime: siteKeyLength=${webSiteKey.trim().length} '
    'firebaseApp=${Firebase.apps.isEmpty ? 'uninitialized' : Firebase.apps.first.name} '
    'origin=${Uri.base.origin} provider=reCAPTCHA Enterprise',
  );
  final webProvider = circumWebAppCheckProvider(
    isWeb: isWeb,
    siteKey: webSiteKey,
  );

  if (isWeb && webProvider == null) {
    return const CircumAppCheckStartup.blocked(
      'Circum security verification is not configured for this version.',
    );
  }

  try {
    await (appCheck ?? FirebaseAppCheck.instance).activate(
      androidProvider: circumAndroidAppCheckProvider(debug: debug),
      appleProvider: circumAppleAppCheckProvider(debug: debug),
      webProvider: webProvider,
    );
    return const CircumAppCheckStartup.enabled();
  } catch (error) {
    final code = error is FirebaseException ? error.code : 'unclassified';
    debugPrint(
      'Admin App Check activation failure: type=${error.runtimeType} code=$code',
    );
    return const CircumAppCheckStartup.blocked(
      'Circum security verification could not start. Please try again.',
    );
  }
}
