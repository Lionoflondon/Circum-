import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

enum SenderAuthAction { createAccount, signIn }

String senderAuthErrorMessage(SenderAuthAction action, Object error) {
  final creating = action == SenderAuthAction.createAccount;
  if (error is TimeoutException) {
    return creating
        ? 'Connection is slow. Account creation could not finish. Try again when your network improves.'
        : 'Connection is slow. Sign in could not finish. Try again when your network improves.';
  }
  if (error is! FirebaseAuthException) {
    return creating
        ? 'Account creation could not be completed. Please try again.'
        : 'Sign in could not be completed. Please try again.';
  }
  switch (error.code) {
    case 'keychain-error':
      return creating
          ? 'Your account may have been created, but access could not be saved on this device. Sign in to continue.'
          : 'Sign in could not be saved on this device. Please restart Circum and try again.';
    case 'email-already-in-use':
      return 'An account already exists for this email. Sign in to continue.';
    case 'invalid-email':
      return 'Enter a valid email address.';
    case 'weak-password':
      return 'Use a stronger password.';
    case 'invalid-credential':
    case 'wrong-password':
    case 'user-not-found':
      return creating
          ? 'An account already exists for this email. Sign in to continue.'
          : 'Sign in failed. Check the email and password.';
    case 'network-request-failed':
      return creating
          ? 'Connection is slow. Account creation could not finish. Try again when your network improves.'
          : 'Connection is slow. Sign in could not finish. Try again when your network improves.';
    case 'too-many-requests':
      return 'Too many attempts. Please wait and try again.';
    case 'operation-not-allowed':
      return creating
          ? 'Account creation is temporarily unavailable. Please try again later.'
          : 'Sign in is temporarily unavailable. Please try again later.';
    case 'wrong-surface':
      return 'This account belongs to another Circum app. Sign in with a Sender account.';
    default:
      return creating
          ? 'Account creation could not be completed. Please try again.'
          : 'Sign in could not be completed. Please try again.';
  }
}

/// Record only a known code, never the SDK message, email, or credential.
String senderAuthFailureCode(Object error) {
  if (error is TimeoutException) return 'timeout';
  if (error is! FirebaseAuthException) return 'unknown';
  const codes = {
    'keychain-error',
    'invalid-app-credential',
    'app-not-authorized',
    'email-already-in-use',
    'invalid-email',
    'weak-password',
    'invalid-credential',
    'wrong-password',
    'user-not-found',
    'network-request-failed',
    'too-many-requests',
    'operation-not-allowed',
    'wrong-surface',
    'sender-no-user',
    'internal-error',
  };
  return codes.contains(error.code) ? error.code : 'unknown';
}
