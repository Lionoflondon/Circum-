import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:circum/app/authentication/phone_verification_deadline.dart';

void main() {
  test('every OTP entry observes initiation and callback together', () {
    final source =
        File('lib/app/authentication/bloc/auth_bloc.dart').readAsStringSync();
    expect(source, isNot(contains('await auth.verifyPhoneNumber(')));
    expect(RegExp(r'await awaitPhoneVerification\(').allMatches(source).length,
        RegExp(r'auth.verifyPhoneNumber\(').allMatches(source).length);
  });
  const deadline = Duration(milliseconds: 10);
  test('native initiation cannot strand the OTP operation', () async {
    final start = Completer<void>();
    final callback = Completer<void>();
    await expectLater(
        awaitPhoneVerification(
            start: () => start.future,
            completion: callback.future,
            timeout: deadline),
        throwsA(isA<TimeoutException>()));
    // Late native errors remain observed after the caller has recovered.
    start.completeError(StateError('late native failure'));
    callback.completeError(StateError('late callback failure'));
    await Future<void>.delayed(Duration.zero);
  });
  test('callback failure is observed while native initiation is pending',
      () async {
    final start = Completer<void>();
    final callback = Completer<void>();
    final result = awaitPhoneVerification(
        start: () => start.future,
        completion: callback.future,
        timeout: deadline);
    final assertion = expectLater(result, throwsA(isA<StateError>()));
    callback.completeError(StateError('provider rejected OTP'));
    await assertion;
    start.complete();
  });
  test('success requires both initiation and callback completion', () async {
    final start = Completer<void>();
    var completed = false;
    final result = awaitPhoneVerification(
            start: () => start.future,
            completion: Future<bool>.value(true),
            timeout: const Duration(seconds: 1))
        .then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    start.complete();
    await result;
    expect(completed, isTrue);
  });
}
