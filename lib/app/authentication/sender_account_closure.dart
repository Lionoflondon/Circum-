import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

enum SenderReauthenticationProvider { emailPassword, google, apple, phone }

class SenderAccountClosureException implements Exception {
  final String message;

  const SenderAccountClosureException(this.message);
}

class SenderAccountClosureSequence {
  static const defaultOperationTimeout = Duration(seconds: 20);
  final Duration operationTimeout;

  const SenderAccountClosureSequence({
    this.operationTimeout = defaultOperationTimeout,
  });

  Future<void> run({
    required Future<void> Function() reauthenticate,
    required Future<void> Function() refreshToken,
    required Future<void> Function() closeApplicationAccount,
    required Future<void> Function() deleteFirebaseIdentity,
    required Future<void> Function() clearLocalSession,
  }) async {
    await reauthenticate().timeout(operationTimeout);
    await refreshToken().timeout(operationTimeout);
    await closeApplicationAccount().timeout(operationTimeout);
    await deleteFirebaseIdentity().timeout(operationTimeout);
    await clearLocalSession().timeout(operationTimeout);
  }
}

/// Coordinates the one recoverable Sender account-closure sequence.
///
/// The backend closes/anonymises application data first. The freshly
/// reauthenticated client then deletes the Firebase Auth identity. If that
/// final identity deletion fails, the user can reauthenticate and retry the
/// idempotent backend operation without losing the authority to finish.
class SenderAccountClosure {
  static const operationTimeout =
      SenderAccountClosureSequence.defaultOperationTimeout;

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final FlutterSecureStorage _storage;
  final GoogleSignIn _googleSignIn;
  final SenderAccountClosureSequence _sequence;

  SenderAccountClosure({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FlutterSecureStorage? storage,
    GoogleSignIn? googleSignIn,
    SenderAccountClosureSequence? sequence,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _storage = storage ?? const FlutterSecureStorage(),
        _googleSignIn = googleSignIn ?? GoogleSignIn(),
        _sequence = sequence ?? const SenderAccountClosureSequence();

  List<SenderReauthenticationProvider> get availableProviders {
    final providers = _auth.currentUser?.providerData
            .map((provider) => provider.providerId)
            .toSet() ??
        const <String>{};
    final available = <SenderReauthenticationProvider>[];
    if (providers.contains('password')) {
      available.add(SenderReauthenticationProvider.emailPassword);
    }
    if (providers.contains('google.com')) {
      available.add(SenderReauthenticationProvider.google);
    }
    if (providers.contains('apple.com')) {
      available.add(SenderReauthenticationProvider.apple);
    }
    if (providers.contains('phone')) {
      available.add(SenderReauthenticationProvider.phone);
    }
    return available;
  }

  Future<void> closeWithEmailPassword(String password) async {
    final user = _requireCurrentUser();
    final email = user.email?.trim();
    if (email == null || email.isEmpty || password.isEmpty) {
      throw const SenderAccountClosureException(
        'Enter your password again before closing your account.',
      );
    }
    await _closeAfterReauthentication(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  Future<void> closeWithGoogle() async {
    final account = await _googleSignIn.signIn().timeout(operationTimeout);
    if (account == null) {
      throw const SenderAccountClosureException(
        'Account closure was cancelled.',
      );
    }
    final authentication = await account.authentication.timeout(
      operationTimeout,
    );
    await _closeAfterReauthentication(
      GoogleAuthProvider.credential(
        accessToken: authentication.accessToken,
        idToken: authentication.idToken,
      ),
    );
  }

  Future<void> closeWithApple() async {
    final rawNonce = _createNonce();
    final nonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final authorization = await SignInWithApple.getAppleIDCredential(
      scopes: const [AppleIDAuthorizationScopes.email],
      nonce: nonce,
    ).timeout(operationTimeout);
    final idToken = authorization.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw const SenderAccountClosureException(
        'Apple could not confirm your identity. Please try again.',
      );
    }
    await _closeAfterReauthentication(
      OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
        accessToken: authorization.authorizationCode,
      ),
    );
  }

  Future<void> closeWithPhoneCredential(PhoneAuthCredential credential) {
    return _closeAfterReauthentication(credential);
  }

  Future<void> _closeAfterReauthentication(AuthCredential credential) async {
    final user = _requireCurrentUser();
    try {
      await _sequence.run(
        reauthenticate: () => user.reauthenticateWithCredential(credential),
        refreshToken: () async {
          await user.getIdToken(true);
        },
        closeApplicationAccount: () async {
          await _functions
              .httpsCallable('closeCircumAccount')
              .call(<String, String>{'accountType': 'sender'});
        },
        deleteFirebaseIdentity: user.delete,
        clearLocalSession: _storage.deleteAll,
      );
    } on TimeoutException {
      throw const SenderAccountClosureException(
        'Account closure timed out. Please sign in again and retry.',
      );
    } on FirebaseAuthException catch (error) {
      throw SenderAccountClosureException(_authErrorMessage(error.code));
    } on FirebaseFunctionsException catch (error) {
      throw SenderAccountClosureException(_functionErrorMessage(error.code));
    }
  }

  User _requireCurrentUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const SenderAccountClosureException(
        'Sign in again before closing your account.',
      );
    }
    return user;
  }

  static String _createNonce([int length = 32]) {
    const alphabet =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static String _authErrorMessage(String code) {
    if (code == 'wrong-password' || code == 'invalid-credential') {
      return 'Your password or sign-in confirmation was not accepted.';
    }
    if (code == 'requires-recent-login') {
      return 'Sign in again before closing your account.';
    }
    return 'Your account could not be closed. Please try again.';
  }

  static String _functionErrorMessage(String code) {
    if (code == 'failed-precondition') {
      return 'Your account cannot be closed until outstanding activity is resolved.';
    }
    if (code == 'unauthenticated') {
      return 'Sign in again before closing your account.';
    }
    return 'Your account could not be closed. Please try again.';
  }
}
