import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const senderBookingQuoteServiceUrl =
    'https://circum-sender-booking-quotes-j2b7cicfwq-uc.a.run.app';

class SenderBookingQuoteApiException implements Exception {
  const SenderBookingQuoteApiException(this.status, this.message);

  final String status;
  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> callSenderBookingQuote(
  Map<String, dynamic> data, {
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  http.Client? client,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  final idToken = await user?.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const SenderBookingQuoteApiException(
      'UNAUTHENTICATED',
      'Sign in to continue.',
    );
  }
  final appCheckToken =
      await (appCheck ?? FirebaseAppCheck.instance).getToken();
  if (appCheckToken == null || appCheckToken.isEmpty) {
    throw const SenderBookingQuoteApiException(
      'UNAUTHENTICATED',
      'Circum security verification is required.',
    );
  }
  return invokeSenderBookingQuote(
    data,
    idToken: idToken,
    appCheckToken: appCheckToken,
    client: client,
    timeout: timeout,
  );
}

Future<Map<String, dynamic>> invokeSenderBookingQuote(
  Map<String, dynamic> data, {
  required String idToken,
  required String appCheckToken,
  http.Client? client,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse('$senderBookingQuoteServiceUrl/createSenderBookingQuote'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $idToken',
            'x-firebase-appcheck': appCheckToken,
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(timeout);
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const SenderBookingQuoteApiException(
        'INTERNAL',
        'Delivery quote could not be prepared. Please try again.',
      );
    }
    if (response.statusCode != 200) {
      final error = payload['error'] as Map?;
      throw SenderBookingQuoteApiException(
        '${error?['status'] ?? 'INTERNAL'}',
        '${error?['message'] ?? 'Delivery quote could not be prepared. Please try again.'}',
      );
    }
    final result = payload['result'];
    if (result is! Map) {
      throw const SenderBookingQuoteApiException(
        'INTERNAL',
        'Delivery quote could not be prepared. Please try again.',
      );
    }
    return Map<String, dynamic>.from(result);
  } finally {
    if (ownsClient) transport.close();
  }
}
