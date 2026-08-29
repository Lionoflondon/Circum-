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

  test('Sender profile update failures leave loading deterministically', () {
    final handler = authBloc.substring(
      authBloc.indexOf('void _handleUpdateUserProfile'),
      authBloc.indexOf('void _handleOpenSettingsApp'),
    );
    expect(handler, contains('emit(state.copyWith(status: Status.loading))'));
    expect(handler, contains('updateDisplayName(event.username).timeout'));
    expect(handler, contains("status: Status.failure"));
    expect(handler, contains("'Profile could not be updated.'"));
  });

  test('Sender OTP request resolves every callback path', () {
    final handler = authBloc.substring(
      authBloc.indexOf('void _handleRequestForOTP'),
      authBloc.indexOf('Future<void> _handleSignInWithGoogle'),
    );
    expect(handler, contains('final completer = Completer<bool>()'));
    expect(handler, contains('if (!completer.isCompleted)'));
    expect(handler, contains('completer.completeError(error)'));
    expect(handler, contains("TimeoutException('phone_otp_request')"));
    expect(
        handler, contains('completer.future.timeout(_authOperationTimeout)'));
    expect(handler, isNot(contains("throw 'Verification failed'")));
    expect(handler, isNot(contains("throw 'Code timed out'")));
  });

  test('Sender OAuth, location, and profile photo paths terminate safely', () {
    expect(authBloc, contains("Google sign-in could not be completed."));
    expect(authBloc, contains('displayName?.trim()'));
    expect(authBloc, isNot(contains('userCredential.user!.displayName!')));
    expect(authBloc, contains('Location could not be enabled.'));
    expect(authBloc, contains('Location settings could not be opened.'));
    expect(authBloc,
        contains('Sign in again before updating your profile photo.'));
    expect(authBloc, contains("putData("));
    expect(authBloc, contains("getDownloadURL()"));
    expect(authBloc, contains("updatePhotoURL(downloadUrl).timeout"));
  });

  test('Sender verification and account-exit operations are bounded', () {
    final verificationHandler = authBloc.substring(
      authBloc.indexOf('Future<void> _handleVerifySentCode'),
      authBloc.indexOf('Future<void> _handleSubmitOTP'),
    );
    expect(verificationHandler, contains('linkWithCredential(credential)'));
    expect(verificationHandler, contains('timeout(_authOperationTimeout)'));
    expect(verificationHandler, contains('signInWithCredential(credential)'));
    expect(verificationHandler, contains('status: Status.failure'));
    expect(verificationHandler,
        contains("'Verification could not be completed.'"));

    final signOutHandler = authBloc.substring(
      authBloc.indexOf('void _handleSignOut'),
      authBloc.indexOf('void _handleDeleteAccount'),
    );
    expect(signOutHandler, contains('auth.signOut().timeout'));
    expect(signOutHandler, contains('storage.deleteAll().timeout'));
    expect(signOutHandler, contains('status: Status.failure'));

    final deleteHandler = authBloc.substring(
      authBloc.indexOf('void _handleDeleteAccount'),
      authBloc.indexOf('void _handleResetPassword'),
    );
    expect(deleteHandler, contains('reauthenticateWithCredential(credential)'));
    expect(deleteHandler, contains("httpsCallable('closeCircumAccount')"));
    expect(deleteHandler, contains('user.delete().timeout'));
    expect(deleteHandler, contains('storage.deleteAll().timeout'));
    expect(deleteHandler, contains('status: Status.failure'));
  });

  test('Sender profile field operations fail visibly and safely', () {
    final phoneHandler = authBloc.substring(
      authBloc.indexOf('void _handleUpdatePhoneNumber'),
      authBloc.indexOf('void _handleUpdateUserProfilePhoto'),
    );
    expect(phoneHandler, contains("_updateSenderProfile(phone: event.value)"));
    expect(phoneHandler, contains("write(key: 'phone', value: event.value)"));
    expect(phoneHandler, contains('timeout(_authOperationTimeout)'));
    expect(phoneHandler, contains('status: Status.failure'));

    final firstNameHandler = authBloc.substring(
      authBloc.indexOf('void _handleUpdateFirstName'),
      authBloc.indexOf('void _handleUpdateLastName'),
    );
    expect(firstNameHandler, contains('updateDisplayName'));
    expect(firstNameHandler, contains('timeout(_authOperationTimeout)'));
    expect(firstNameHandler, contains('status: Status.failure'));

    final lastNameHandler = authBloc.substring(
      authBloc.indexOf('void _handleUpdateLastName'),
      authBloc.indexOf('void _handleSetErrorMessage'),
    );
    expect(lastNameHandler, contains('updateDisplayName'));
    expect(lastNameHandler, contains('timeout(_authOperationTimeout)'));
    expect(lastNameHandler, contains('status: Status.failure'));
  });

  test('Sender email confirmation cannot leave a loading state forever', () {
    final handler = authBloc.substring(
      authBloc.indexOf('void _handleConfirmEmailVerification'),
      authBloc.indexOf('void _handleUpdatePhoneNumber'),
    );
    expect(handler, contains('emit(state.copyWith(status: Status.loading))'));
    expect(handler, contains('reload().timeout(_authOperationTimeout)'));
    expect(handler, contains('status: Status.unverifiedEmail'));
    expect(handler, contains('status: Status.failure'));
    expect(
        handler,
        contains(
            "'Email verification could not be confirmed. Please try again.'"));
  });
}
