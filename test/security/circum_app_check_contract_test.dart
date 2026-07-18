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
}
