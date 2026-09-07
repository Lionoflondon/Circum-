import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual iOS notification integration bridges APNs to Firebase', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(info, contains('<key>FirebaseAppDelegateProxyEnabled</key>'));
    expect(info, contains('<false/>'));
    expect(appDelegate, contains('import FirebaseMessaging'));
    expect(appDelegate,
        contains('didRegisterForRemoteNotificationsWithDeviceToken'));
    expect(
        appDelegate, contains('Messaging.messaging().apnsToken = deviceToken'));
    expect(main, contains('FirebaseMessaging.instance.requestPermission('));
    expect(main, contains('setForegroundNotificationPresentationOptions('));
  });

  test('Sender privacy manifest does not falsely declare tracking', () {
    final manifest =
        File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    expect(manifest, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
    expect(manifest, isNot(contains('<dict/>')));
  });
}
