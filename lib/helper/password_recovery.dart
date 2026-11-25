import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:http/http.dart' as http;

const passwordRecoveryAcknowledgement =
    'If an account uses this email, you will receive a secure CIRCUM password reset link. Check your inbox and spam folder.';

class PasswordRecoveryException implements Exception {
  const PasswordRecoveryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Signed-out recovery requires App Check, never an existing Auth session.
/// One request only: an uncertain response must not trigger a second mail path.
Future<void> requestCircumPasswordReset({
  required String email,
  required String application,
  Future<String?> Function()? getAppCheckToken,
  http.Client? client,
}) async {
  final normalized = email.trim().toLowerCase();
  if (!RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$').hasMatch(normalized) ||
      normalized.length > 254 ||
      !{'sender', 'rider'}.contains(application)) {
    throw const PasswordRecoveryException('Enter a valid email address.');
  }
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final token =
        await (getAppCheckToken ?? () => FirebaseAppCheck.instance.getToken())()
            .timeout(const Duration(seconds: 15));
    if (token == null || token.isEmpty) {
      throw const PasswordRecoveryException(
          'Security verification could not finish. Please try again.');
    }
    final response = await transport
        .post(
          Uri.parse(
              'https://circum-account-bootstrap-516426305461.us-central1.run.app/requestCircumPasswordReset'),
          headers: {
            'content-type': 'application/json',
            'x-firebase-appcheck': token,
          },
          body: jsonEncode({
            'data': {'email': normalized, 'client': application},
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 429) {
      throw const PasswordRecoveryException(
          'Too many requests. Please wait a few minutes and try again.');
    }
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        decoded is! Map ||
        decoded['result'] is! Map ||
        decoded['result']['ok'] != true) {
      throw const PasswordRecoveryException(
          'Password recovery is temporarily unavailable. Please try again shortly.');
    }
  } on PasswordRecoveryException {
    rethrow;
  } on TimeoutException {
    throw const PasswordRecoveryException(
        'The request took too long. Check your email before trying again.');
  } catch (_) {
    throw const PasswordRecoveryException(
        'Password recovery is temporarily unavailable. Please try again shortly.');
  } finally {
    if (ownsClient) transport.close();
  }
}
