import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public website owns the Sender login and signup entry flow', () {
    final publicSource = File('lib/web_sender_app.dart').readAsStringSync();

    expect(publicSource, contains('enum _PublicAuthMode'));
    expect(publicSource, contains('Welcome to Circum'));
    expect(
      publicSource,
      contains('Sign in to continue or create a new account.'),
    );
    expect(publicSource, contains("child: const Text('Sign up')"));
    expect(publicSource, contains("child: Text(\n                  'Log in'"));
    expect(publicSource, contains("label: 'First name'"));
    expect(publicSource, contains("label: 'Last name'"));
    expect(publicSource, contains("label: 'Phone number'"));
    expect(publicSource, contains("label: 'Confirm password'"));
    expect(publicSource, contains("label: 'Accept Terms'"));
    expect(publicSource, contains("label: 'Remember me'"));
    expect(publicSource, contains('sendPasswordResetEmail'));
    expect(publicSource, contains('signInWithEmailAndPassword'));
    expect(publicSource, contains('createUserWithEmailAndPassword'));
    expect(publicSource, contains('signInWithPopup'));
    expect(publicSource, contains("'source': 'public_sender_web'"));
  });

  test('Sender app landing no longer carries the public auth entry redesign',
      () {
    final senderAppSource = File(
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ).readAsStringSync();

    expect(senderAppSource, isNot(contains('Welcome to Circum')));
    expect(senderAppSource, isNot(contains('Sign up')));
    expect(senderAppSource, isNot(contains("label: 'Accept Terms'")));
  });
}
