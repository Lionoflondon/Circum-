import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

enum SenderAuthAction { createAccount, signIn }

String senderAuthErrorMessage(SenderAuthAction action, Object error) {
  final creating = action == SenderAuthAction.createAccount;
  if (error is TimeoutException) {
    return creating
        ? 'Account creation timed out. Please try again.'
        : 'Sign in timed out. Please try again.';
  }
  if (error is! FirebaseAuthException) {
    return creating
        ? 'Account creation could not be completed. Please try again.'
        : 'Sign in could not be completed. Please try again.';
  }
  switch (error.code) {
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
      return 'Check your connection and try again.';
    case 'too-many-requests':
      return 'Too many attempts. Please wait and try again.';
    case 'operation-not-allowed':
      return creating
          ? 'Account creation is temporarily unavailable. Please try again later.'
          : 'Sign in is temporarily unavailable. Please try again later.';
    default:
      return creating
          ? 'Account creation could not be completed. Please try again.'
          : 'Sign in could not be completed. Please try again.';
  }
}
