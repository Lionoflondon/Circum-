import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circum/app/authentication/sender_email_auth.dart';

class Credential extends Fake implements UserCredential {}

class Auth extends Fake implements FirebaseAuth {
  int creates = 0;
  int signIns = 0;
  Object? createError;
  final credential = Credential();
  @override
  Future<UserCredential> createUserWithEmailAndPassword(
      {required String email, required String password}) async {
    creates++;
    if (createError != null) throw createError!;
    return credential;
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword(
      {required String email, required String password}) async {
    signIns++;
    return credential;
  }
}

void main() {
  Future<UserCredential> run(Auth auth, bool create) => authenticateSenderEmail(
        auth: auth,
        email: 'sender@example.invalid',
        password: 'correct-password',
        createAccount: create,
        timeout: const Duration(seconds: 1),
      );
  test(
      'existing-email create fails without signing into or returning the existing account',
      () async {
    final auth = Auth()
      ..createError = FirebaseAuthException(code: 'email-already-in-use');
    await expectLater(
        run(auth, true),
        throwsA(isA<FirebaseAuthException>()
            .having((e) => e.code, 'code', 'email-already-in-use')));
    expect(auth.creates, 1);
    expect(auth.signIns, 0);
  });
  test('network failure during create never falls back to sign-in', () async {
    final auth = Auth()
      ..createError = FirebaseAuthException(code: 'network-request-failed');
    await expectLater(run(auth, true), throwsA(isA<FirebaseAuthException>()));
    expect(auth.signIns, 0);
  });
  test('new-account success and explicit sign-in keep their distinct semantics',
      () async {
    final createAuth = Auth();
    expect(await run(createAuth, true), same(createAuth.credential));
    expect(createAuth.creates, 1);
    expect(createAuth.signIns, 0);
    final loginAuth = Auth();
    expect(await run(loginAuth, false), same(loginAuth.credential));
    expect(loginAuth.creates, 0);
    expect(loginAuth.signIns, 1);
  });
  test(
      'interactive mobile auth retains ownership of profile and referral completion',
      () {
    final home = File('lib/app/sender_mobile/sender_mobile_home.dart')
        .readAsStringSync();
    expect(
        home,
        contains(
            'if (user != null && _entry == _SenderEntryScreen.auth) return;'));
    expect(home, contains("'sender_mobile.restore.ensure'"));
    final authenticate = home.substring(
        home.indexOf('Future<SenderAuthCommitResult> _authenticateSender('),
        home.indexOf('class _AmbientOrbs'));
    expect(authenticate, contains('authenticateSenderEmail'));
    expect(authenticate, isNot(contains("email-already-in-use")));
    expect(authenticate, contains("httpsCallable('attachReferralCode')"));
    expect(
        authenticate, contains('if (accountCreated && bootstrap.succeeded)'));
  });
}
