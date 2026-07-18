import 'dart:io';

import 'package:circum/app/security/circum_app_check.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Circum App Check provider policy is release-safe', () {
    expect(
      circumAndroidAppCheckProvider(debug: true),
      AndroidProvider.debug,
    );
    expect(
      circumAndroidAppCheckProvider(debug: false),
      AndroidProvider.playIntegrity,
    );
    expect(
      circumAppleAppCheckProvider(debug: true),
      AppleProvider.debug,
    );
    expect(
      circumAppleAppCheckProvider(debug: false),
      AppleProvider.appAttestWithDeviceCheckFallback,
    );
  });

  test('Circum web App Check requires an explicit Enterprise site key', () {
    final appCheckSource =
        File('lib/app/security/circum_app_check.dart').readAsStringSync();

    expect(
      appCheckSource,
      contains('CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY'),
    );
    expect(
      appCheckSource,
      isNot(contains('CIRCUM_RECAPTCHA_ENTERPRISE_SITE_KEY')),
    );
    expect(
      appCheckSource,
      isNot(contains('RIDER_RECAPTCHA_ENTERPRISE_SITE_KEY')),
    );
    expect(
      circumWebAppCheckProvider(isWeb: true, siteKey: ''),
      isNull,
    );
    expect(
      circumWebAppCheckProvider(isWeb: false, siteKey: ''),
      isNull,
    );
    expect(
      circumWebAppCheckProvider(isWeb: true, siteKey: 'site-key'),
      isA<ReCaptchaEnterpriseProvider>(),
    );
  });

  test('Circum production entrypoints initialize App Check after Firebase', () {
    for (final path in [
      'lib/main.dart',
      'lib/main_sender_web.dart',
      'lib/main_public_web.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final firebaseInit = source.indexOf('Firebase.initializeApp');
      final appCheckInit = source.indexOf('initializeCircumAppCheck');

      expect(firebaseInit, isNonNegative, reason: path);
      expect(appCheckInit, greaterThan(firebaseInit), reason: path);
      expect(source, contains('StartupBlocked'), reason: path);
    }
  });

  test('Circum App Check source never logs or stores App Check token values',
      () {
    final source =
        File('lib/app/security/circum_app_check.dart').readAsStringSync();
    final executableLines = source
        .split('\n')
        .map((line) => line.trimLeft())
        .where((line) => !line.startsWith('//'))
        .join('\n');

    expect(executableLines, isNot(contains('print(')));
    expect(executableLines, isNot(contains('debugPrint(')));
    expect(executableLines, isNot(contains('getToken(')));
    expect(
        executableLines, isNot(contains('setTokenAutoRefreshEnabled(false)')));
  });

  test('Circum web build scripts pass the shared App Check site key', () {
    for (final path in [
      'scripts/build_sender_app_web.sh',
      'scripts/build_public_web.sh',
      'scripts/build_admin_web.sh',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY'),
        reason: path,
      );
      expect(
        source,
        contains('--dart-define=CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY='),
        reason: path,
      );
      expect(
        source,
        isNot(contains('CIRCUM_RECAPTCHA_ENTERPRISE_SITE_KEY')),
        reason: path,
      );
      expect(
        source,
        isNot(contains('RIDER_RECAPTCHA_ENTERPRISE_SITE_KEY')),
        reason: path,
      );
    }
  });

  test(
      'Circum release-critical payment and messaging paths do not log payloads',
      () {
    for (final path in [
      'lib/messaging.dart',
      'lib/helper/chats_help.dart',
      'lib/app/account/bloc/account_bloc.dart',
    ]) {
      final source = File(path).readAsLinesSync();
      final executableLines = source
          .map((line) => line.trimLeft())
          .where((line) => !line.startsWith('//'))
          .join('\n');

      expect(executableLines, isNot(contains('print(')), reason: path);
      expect(executableLines, isNot(contains('debugPrint(')), reason: path);
      expect(executableLines, isNot(contains('print(paymentIntentResult')),
          reason: path);
      expect(executableLines, isNot(contains('Message data:')), reason: path);
    }
  });

  test('Circum runtime Maps keys are provided by configuration', () {
    final hardcodedMapsKey = RegExp(r'AIza[0-9A-Za-z_-]+');
    for (final path in [
      'lib/web_sender_app.dart',
      'lib/app/send_package/bloc/send_package_bloc.dart',
      'android/app/src/main/AndroidManifest.xml',
      'ios/Runner/AppDelegate.swift',
      'ios/Runner/Info.plist',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(matches(hardcodedMapsKey)), reason: path);
    }

    expect(
      File('lib/web_sender_app.dart').readAsStringSync(),
      contains("String.fromEnvironment(\n  'GOOGLE_PLACES_API_KEY'"),
    );
    expect(
      File('lib/app/send_package/bloc/send_package_bloc.dart')
          .readAsStringSync(),
      contains("String.fromEnvironment('GOOGLE_MAPS_DIRECTIONS_API_KEY')"),
    );
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains(r'${googleMapsApiKey}'),
    );
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      contains(r'$(GOOGLE_MAPS_API_KEY)'),
    );
  });
}
