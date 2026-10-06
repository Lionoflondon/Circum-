import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender development builds isolate Keychain access to their own app',
      () {
    final source = File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(source, contains('<key>keychain-access-groups</key>'));
    expect(source, contains(r'$(AppIdentifierPrefix)$(CFBundleIdentifier)'));
    expect(source, isNot(contains('<string>*</string>')));
  });
}
