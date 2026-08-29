import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final home =
      File('lib/app/sender_mobile/sender_mobile_home.dart').readAsStringSync();
  final authBloc =
      File('lib/app/authentication/bloc/auth_bloc.dart').readAsStringSync();
  final app = File('lib/app.dart').readAsStringSync();

  test('production Sender auth no longer depends on preview terminology', () {
    expect(home, contains('senderAuthEnabled'));
    expect(app, contains('SenderMobileHome(senderAuthEnabled: true)'));
    expect(home, isNot(contains('previewAuthEnabled')));
    expect(home, isNot(contains('Preview authentication')));
    expect(home, isNot(contains('Preview sign-in')));
    expect(home, isNot(contains('Preparing preview')));
  });

  test('visible Sender auth operations are bounded', () {
    expect(home, contains('_senderAuthOperationTimeout'));
    expect(home, contains('_senderAuthRestoreTimeout'));
    expect(home, contains('setPersistence(Persistence.LOCAL)'));
    expect(home, contains('authStateChanges()'));
    expect(home, contains('createUserWithEmailAndPassword'));
    expect(home, contains('signInWithEmailAndPassword'));
    expect(home, contains("httpsCallable('ensureSenderAccount')"));
    expect(home, contains('getIdToken(true)'));
    expect(home, contains('.timeout('));
  });

  test('legacy Sender AuthBloc auth operations are bounded and do not rethrow',
      () {
    expect(authBloc, contains('_authOperationTimeout'));
    expect(authBloc, contains('readAll().timeout'));
    expect(authBloc, contains('signInWithEmailAndPassword'));
    expect(authBloc, contains('createUserWithEmailAndPassword'));
    expect(authBloc, contains('sendEmailVerification()'));
    expect(authBloc, contains('sendPasswordResetEmail'));
    expect(authBloc, contains('.timeout(_authOperationTimeout)'));
    expect(
        authBloc, isNot(contains('throw Exception(err.message.toString())')));
    expect(authBloc, isNot(contains('throw Exception(err.toString())')));
  });
}
