import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender profile settings expose secure account closure flow', () {
    final app = File('${Directory.current.path}/lib/web_sender_app.dart')
        .readAsStringSync();

    expect(app, contains('Close Account'));
    expect(app,
        contains('Permanently delete your Circum account and personal data.'));
    expect(app, contains('Close your Circum account?'));
    expect(app, contains('Type DELETE to confirm.'));
    expect(app, contains("httpsCallable('closeCircumAccount')"));
    expect(app, contains("'accountType': 'sender'"));
    expect(app, contains('reauthenticateWithCredential'));
    expect(app, contains('reauthenticateWithPopup'));
    expect(app, isNot(contains("storage.write(key: 'password'")));
  });
}
