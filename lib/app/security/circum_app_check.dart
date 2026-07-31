import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
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
  final webProvider = circumWebAppCheckProvider(
    isWeb: isWeb,
    siteKey: webSiteKey,
  );

  if (isWeb && webProvider == null) {
    return const CircumAppCheckStartup._(
      enabled: false,
      blockStartup: false,
      message:
          'Circum security verification is not configured for this version.',
    );
  }

  try {
    final activation = (appCheck ?? FirebaseAppCheck.instance).activate(
      androidProvider: circumAndroidAppCheckProvider(debug: debug),
      appleProvider: circumAppleAppCheckProvider(debug: debug),
      webProvider: webProvider,
    );
    if (isWeb) {
      await activation.timeout(const Duration(seconds: 3));
    } else {
      await activation;
    }
    return const CircumAppCheckStartup.enabled();
  } on TimeoutException {
    return const CircumAppCheckStartup._(
      enabled: false,
      blockStartup: false,
      message:
          'Circum security verification is taking longer than expected.',
    );
  } catch (_) {
    return const CircumAppCheckStartup._(
      enabled: false,
      blockStartup: false,
      message:
          'Circum security verification could not start. Please try again.',
    );
  }
}
