import 'dart:io';

import 'package:circum/app/admin/security/admin_app_check.dart' as admin;
import 'package:circum/app/security/circum_app_check.dart' as sender;
import 'package:circum/website/shared/security/circum_website_app_check.dart'
    as website;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Circum App Check provider policy is release-safe', () {
    expect(
      sender.circumAndroidAppCheckProvider(debug: true),
      AndroidProvider.debug,
    );
    expect(
      sender.circumAndroidAppCheckProvider(debug: false),
      AndroidProvider.playIntegrity,
    );
    expect(
      sender.circumAppleAppCheckProvider(debug: true),
      AppleProvider.debug,
    );
    expect(
      sender.circumAppleAppCheckProvider(debug: false),
      AppleProvider.appAttestWithDeviceCheckFallback,
    );
  });

  test('Circum web App Check requires product-specific Enterprise site keys',
      () {
    final appCheckSource =
        File('lib/app/security/circum_app_check.dart').readAsStringSync();
    final websiteAppCheckSource =
        File('lib/website/shared/security/circum_website_app_check.dart')
            .readAsStringSync();
    final adminAppCheckSource =
        File('lib/app/admin/security/admin_app_check.dart').readAsStringSync();

    expect(
      appCheckSource,
      contains('CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY'),
    );
    expect(
      websiteAppCheckSource,
      contains('PUBLIC_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY'),
    );
    expect(
      websiteAppCheckSource,
      isNot(contains('CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY')),
    );
    expect(
      adminAppCheckSource,
      contains('CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY'),
    );
    for (final source in [
      appCheckSource,
      websiteAppCheckSource,
      adminAppCheckSource,
    ]) {
      expect(source, isNot(contains('CIRCUM_RECAPTCHA_ENTERPRISE_SITE_KEY')));
      expect(source, isNot(contains('RIDER_RECAPTCHA_ENTERPRISE_SITE_KEY')));
      expect(
          source, isNot(contains('RIDER_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY')));
    }
    expect(
      sender.circumWebAppCheckProvider(isWeb: true, siteKey: ''),
      isNull,
    );
    expect(
      website.circumWebAppCheckProvider(isWeb: false, siteKey: ''),
      isNull,
    );
    expect(
      admin.circumWebAppCheckProvider(isWeb: true, siteKey: 'site-key'),
      isA<ReCaptchaEnterpriseProvider>(),
    );
  });

  test('Circum production entrypoints initialize App Check after Firebase', () {
    for (final path in [
      'lib/main.dart',
      'lib/main_public_web.dart',
      'lib/main_admin_web.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final firebaseInit = source.indexOf('Firebase.initializeApp');
      final appCheckInit = source.indexOf('initializeCircumAppCheck');

      expect(firebaseInit, isNonNegative, reason: path);
      expect(appCheckInit, greaterThan(firebaseInit), reason: path);
      expect(source, contains('blockStartup'), reason: path);
    }
  });

  test('Circum App Check source never logs or stores App Check token values',
      () {
    final source = [
      'lib/app/security/circum_app_check.dart',
      'lib/website/shared/security/circum_website_app_check.dart',
      'lib/app/admin/security/admin_app_check.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
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

  test('Circum web build scripts pass product-specific App Check site keys',
      () {
    final publicBuild = File('scripts/build_public_web.sh').readAsStringSync();
    final senderBuild =
        File('scripts/build_sender_app_web.sh').readAsStringSync();
    final adminBuild = File('scripts/build_admin_web.sh').readAsStringSync();

    expect(publicBuild, contains('PUBLIC_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY'));
    expect(
      publicBuild,
      contains('--dart-define=PUBLIC_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY='),
    );
    expect(
      publicBuild,
      isNot(contains('CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY')),
    );

    expect(senderBuild, contains('CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY'));
    expect(
      senderBuild,
      contains('--dart-define=CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY='),
    );

    expect(adminBuild, contains('CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY'));
    expect(
      adminBuild,
      contains('--dart-define=CIRCUM_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY='),
    );

    for (final source in [publicBuild, senderBuild, adminBuild]) {
      expect(source, isNot(contains('CIRCUM_RECAPTCHA_ENTERPRISE_SITE_KEY')));
      expect(source, isNot(contains('RIDER_RECAPTCHA_ENTERPRISE_SITE_KEY')));
      expect(
          source, isNot(contains('RIDER_WEB_RECAPTCHA_ENTERPRISE_SITE_KEY')));
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
      'lib/website/shared/circum_website_app.dart',
      'lib/app/send_package/bloc/send_package_bloc.dart',
      'android/app/src/main/AndroidManifest.xml',
      'ios/Runner/AppDelegate.swift',
      'ios/Runner/Info.plist',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(matches(hardcodedMapsKey)), reason: path);
    }

    expect(
      File('lib/website/shared/circum_website_app.dart').readAsStringSync(),
      contains("String.fromEnvironment('GOOGLE_PLACES_API_KEY')"),
    );
    final senderRouteSource =
        File('lib/app/send_package/bloc/send_package_bloc.dart')
            .readAsStringSync();
    final usesLegacyConfiguredKey = senderRouteSource.contains(
      "String.fromEnvironment('GOOGLE_MAPS_DIRECTIONS_API_KEY')",
    );
    final usesProtectedRouteCallable =
        senderRouteSource.contains("'getSenderRoutePreview'");
    expect(
      usesLegacyConfiguredKey != usesProtectedRouteCallable,
      isTrue,
      reason: 'Sender must use exactly one protected route credential path.',
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
