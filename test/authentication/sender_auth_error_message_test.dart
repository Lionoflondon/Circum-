import 'dart:async';

import 'package:circum/app/authentication/sender_auth_error_message.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('create-account failures never use sign-in wording', () {
    final message = senderAuthErrorMessage(
      SenderAuthAction.createAccount,
      StateError('hidden'),
    );
    expect(
      message,
      'Account creation could not be completed. Please try again.',
    );
    expect(message.toLowerCase(), isNot(contains('sign in could not')));
  });

  test('existing email has create-account recovery guidance', () {
    final message = senderAuthErrorMessage(
      SenderAuthAction.createAccount,
      FirebaseAuthException(code: 'email-already-in-use'),
    );
    expect(message, contains('already exists'));
    expect(message, contains('Sign in'));
  });

  test('create and sign-in timeouts are action aware', () {
    expect(
      senderAuthErrorMessage(
        SenderAuthAction.createAccount,
        TimeoutException('create'),
      ),
      'Connection is slow. Account creation could not finish. Try again when your network improves.',
    );
    expect(
      senderAuthErrorMessage(
        SenderAuthAction.signIn,
        TimeoutException('sign-in'),
      ),
      'Connection is slow. Sign in could not finish. Try again when your network improves.',
    );
  });

  test('network and credential failures remain customer safe', () {
    expect(
      senderAuthErrorMessage(
        SenderAuthAction.createAccount,
        FirebaseAuthException(code: 'network-request-failed'),
      ),
      'Connection is slow. Account creation could not finish. Try again when your network improves.',
    );
    expect(
      senderAuthErrorMessage(
        SenderAuthAction.signIn,
        FirebaseAuthException(code: 'invalid-credential'),
      ),
      'Sign in failed. Check the email and password.',
    );
  });
}
