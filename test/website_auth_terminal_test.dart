import 'dart:async';
import 'dart:io';

import 'package:circum/website/shared/policies/web_auth_terminal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const timeout = Duration(milliseconds: 10);
  test('remote failure retains authenticated account subscriptions', () async {
    var cancelled = false;
    expect(
        await finishWebSignOut(
          signOut: () async => throw StateError('provider failure'),
          cancelSubscriptions: () async {
            cancelled = true;
          },
          timeout: timeout,
        ),
        isFalse);
    expect(cancelled, isFalse);
  });
  test('remote timeout is terminal and retains subscriptions', () async {
    var cancelled = false;
    expect(
        await finishWebSignOut(
          signOut: () => Completer<void>().future,
          cancelSubscriptions: () async {
            cancelled = true;
          },
          timeout: timeout,
        ),
        isFalse);
    expect(cancelled, isFalse);
  });
  test('confirmed signout permits account clearing despite cleanup timeout',
      () async {
    expect(
        await finishWebSignOut(
          signOut: () async {},
          cancelSubscriptions: () => Completer<void>().future,
          timeout: timeout,
        ),
        isTrue);
  });
  test('confirmed signout permits account clearing despite cleanup failure',
      () async {
    expect(
        await finishWebSignOut(
          signOut: () async {},
          cancelSubscriptions: () async => throw StateError('cleanup'),
          timeout: timeout,
        ),
        isTrue);
  });
  test('signout completes before subscriptions are cancelled', () async {
    final steps = <String>[];
    expect(
        await finishWebSignOut(
          signOut: () async {
            steps.add('signed out');
          },
          cancelSubscriptions: () async {
            steps.add('cancelled');
          },
          timeout: timeout,
        ),
        isTrue);
    expect(steps, ['signed out', 'cancelled']);
  });
  final source =
      File('lib/website/shared/circum_website_app.dart').readAsStringSync();
  for (final surface in ['Sender', 'Rider']) {
    test('$surface reset maps timeout and unknown errors and clears busy', () {
      final start = source.indexOf('Future<void> _send${surface}PasswordReset');
      final end = source.indexOf(
          'Future<UserCredential> _reauthenticate$surface', start);
      final handler = source.substring(start, end);
      expect(
          handler,
          contains(
              'sendPasswordResetEmail(email: email)\n          .timeout(webAuthOperationTimeout)'));
      expect(handler, contains('on TimeoutException'));
      expect(handler, contains('catch (_)'));
      expect(handler, contains('finally'));
      expect(handler, contains('= false'));
    });
    test('$surface logout preserves subscriptions until remote success', () {
      final start = source.indexOf('Future<void> _signOut$surface()');
      final end = source.indexOf('\n  Future<', start + 1);
      final handler = source.substring(start, end);
      expect(handler, contains('finishWebSignOut('));
      expect(handler, contains('if (!signedOut)'));
      expect(handler, contains('finally'));
      expect(handler, contains('= null'));
    });
  }
}
