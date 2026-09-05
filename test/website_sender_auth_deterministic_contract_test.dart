import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final home =
      File('lib/app/sender_mobile/sender_mobile_home.dart').readAsStringSync();
  final authBloc =
      File('lib/app/authentication/bloc/auth_bloc.dart').readAsStringSync();
  final accountClosure =
      File('lib/app/authentication/sender_account_closure.dart')
          .readAsStringSync();
  final profile = File('lib/app/sender_mobile/sender_mobile_profile.dart')
      .readAsStringSync();
  final app = File('lib/app.dart').readAsStringSync();
  final website =
      File('lib/website/shared/circum_website_app.dart').readAsStringSync();

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
    final emailAuthFile = File('lib/app/authentication/sender_email_auth.dart');
    final emailAuth =
        emailAuthFile.existsSync() ? emailAuthFile.readAsStringSync() : home;
    expect(emailAuth, contains('createUserWithEmailAndPassword'));
    expect(emailAuth, contains('signInWithEmailAndPassword'));
    final authority =
        File('lib/app/sender_mobile/sender_profile_authority.dart')
            .readAsStringSync();
    expect('$home$authority', contains("httpsCallable('ensureSenderAccount')"));
    expect(home, contains(".load('sender_mobile.auth.profile')"));
    expect(home, contains('getIdToken(true)'));
    expect(home, contains('.timeout('));
  });

  test('Sender web auth and post-auth bootstrap are bounded and terminal', () {
    final signIn = website.substring(
      website.indexOf('Future<void> _signInSender()'),
      website.indexOf('Future<void> _signUpSender()'),
    );
    final signUp = website.substring(
      website.indexOf('Future<void> _signUpSender()'),
      website.indexOf('Future<void> _sendSenderPasswordReset()'),
    );
    for (final handler in [signIn, signUp]) {
      expect(handler, contains('_senderAuthOperationTimeout'));
      expect(handler, contains('on TimeoutException'));
      expect(handler, contains('catch (_)'));
      expect(handler, contains('_senderAuthBusy = false'));
    }
    expect(signUp, contains('account may have been created'));
    expect(signUp, isNot(contains('Sign in could not be completed')));
  });

  test('legacy Sender AuthBloc auth operations are bounded and do not rethrow',
      () {
    expect(authBloc, contains('_authOperationTimeout'));
    expect(authBloc, contains('_hydrateSenderSession'));
    expect(authBloc, contains('_hydrateSenderSessionRecoverably'));
    expect(authBloc, contains('SenderProfileAuthority'));
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
    expect(handler, contains('await awaitPhoneVerification('));
    expect(handler, contains('completion: completer.future'));
    expect(handler, contains('timeout: _authOperationTimeout'));
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

  test('SOURCE CONTRACT: Google, Apple, and phone provider paths are terminal',
      () {
    final apple = authBloc.substring(
      authBloc.indexOf('Future<void> _handleSignInWithAppleAuth'),
      authBloc.indexOf('void _handleRequestForOTP'),
    );
    final google = authBloc.substring(
      authBloc.indexOf('Future<void> _handleSignInWithGoogle'),
      authBloc.indexOf('Future<void> _handleVerifySentCode'),
    );
    final phone = authBloc.substring(
      authBloc.indexOf('void _handleRequestForOTP'),
      authBloc.indexOf('Future<void> _handleSignInWithGoogle'),
    );

    expect(apple, contains('getAppleIDCredential'));
    expect(apple, contains('rawNonce: rawNonce'));
    expect(
      apple,
      isNot(contains('accessToken: appleCredential.authorizationCode')),
    );
    expect(apple, contains('_hydrateSenderSessionRecoverably'));
    expect(apple, contains('status: Status.failure'));
    expect(google, contains('if (googleSignInAccount == null)'));
    expect(google, contains('_hydrateSenderSessionRecoverably'));
    expect(google, contains('status: Status.failure'));
    expect(phone, contains('verificationCompleted'));
    expect(phone, contains('verificationFailed'));
    expect(phone, contains('codeSent'));
    expect(phone, contains('codeAutoRetrievalTimeout'));
    expect(phone, contains('if (!completer.isCompleted)'));
    expect(phone, contains('await awaitPhoneVerification('));
    expect(phone, contains('completion: completer.future'));
    expect(phone, contains('timeout: _authOperationTimeout'));
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
      authBloc.indexOf('void _handleResetPassword'),
    );
    expect(signOutHandler, contains('auth.signOut().timeout'));
    expect(signOutHandler, contains('storage.deleteAll().timeout'));
    expect(signOutHandler, contains('status: Status.failure'));

    expect(authBloc, isNot(contains('void _handleDeleteAccount')));
    expect(accountClosure, contains('reauthenticateWithCredential'));
    expect(accountClosure, contains("httpsCallable('closeCircumAccount')"));
    expect(accountClosure, contains('deleteFirebaseIdentity: user.delete'));
    expect(accountClosure, contains('clearLocalSession: _storage.deleteAll'));
    expect(accountClosure, contains('getIdToken(true)'));
    expect(accountClosure, contains('rawNonce: rawNonce'));
    expect(profile, contains('SenderAccountClosure'));
    expect(accountClosure, contains('closeWithPhoneCredential'));
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
  test(
      'web signup, restore and wallet refresh converge on checked account bootstrap',
      () {
    final signup = website.substring(
        website.indexOf('Future<void> _signUpSender()'),
        website.indexOf('Future<void> _sendSenderPasswordReset()'));
    expect(signup.indexOf('_allowSenderUser(user)'),
        lessThan(signup.indexOf("httpsCallable('updateSenderProfile')")));
    expect(signup.indexOf("httpsCallable('updateSenderProfile')"),
        lessThan(signup.indexOf("httpsCallable('attachReferralCode')")));
    final access = website.substring(
        website.indexOf('Future<bool> _allowSenderUser('),
        website.indexOf('Future<Set<CircumRole>> _rolesForSenderUser('));
    expect(access, contains('ensureWebSenderBootstrap'));
    expect(access, contains("httpsCallable('ensureSenderAccount')"));
    final balance = website.substring(
        website.indexOf('Future<void> _loadSenderRothBalance()'),
        website.indexOf('Future<void> _showLegendCelebration('));
    expect(balance.indexOf('_allowSenderUser(user)'),
        lessThan(balance.indexOf("httpsCallable('getSenderRothBalance')")));
  });
}
