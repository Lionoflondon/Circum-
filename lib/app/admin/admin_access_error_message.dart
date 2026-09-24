import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

String adminAccessErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'network-request-failed':
        return 'Could not verify your sign-in. Check your connection and try again.';
      case 'user-token-expired':
      case 'invalid-user-token':
      case 'user-disabled':
        return 'Your sign-in session is no longer valid. Sign in again.';
      default:
        return 'Could not verify your sign-in. Sign in again and retry.';
    }
  }

  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Your sign-in session expired. Sign in again.';
      case 'permission-denied':
        return 'Your account was denied Admin access. Ask an existing Admin to review its access.';
      case 'failed-precondition':
        return 'Admin security verification could not be completed. Refresh the page and retry.';
      case 'unavailable':
      case 'deadline-exceeded':
      case 'resource-exhausted':
      case 'internal':
        return 'Admin access is temporarily unavailable. Wait a moment and retry.';
      default:
        return 'Admin access could not be verified. Refresh the page and retry.';
    }
  }

  return 'Admin access could not be verified. Refresh the page and retry.';
}
