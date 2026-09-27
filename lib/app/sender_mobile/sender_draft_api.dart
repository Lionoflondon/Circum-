import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const senderDraftServiceUrl =
    'https://circum-sender-drafts-516426305461.us-central1.run.app';

class SenderDraftApiException implements Exception {
  const SenderDraftApiException(this.status, this.message);

  final String status;
  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> callSenderDraft(
  String operation,
  Map<String, dynamic> data, {
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) async {
  const operations = {'saveSenderDraft', 'loadSenderDraft', 'deleteSenderDraft'};
  if (!operations.contains(operation)) {
    throw ArgumentError.value(operation, 'operation', 'Unsupported Sender draft operation');
  }
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  final idToken = await user?.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const SenderDraftApiException('UNAUTHENTICATED', 'Sign in to continue.');
  }
  final appCheckToken = await (appCheck ?? FirebaseAppCheck.instance).getToken();
  if (appCheckToken == null || appCheckToken.isEmpty) {
    throw const SenderDraftApiException(
      'FAILED_PRECONDITION',
      'Circum security verification is required.',
    );
  }
  return invokeSenderDraft(
    operation,
    data,
    idToken: idToken,
    appCheckToken: appCheckToken,
    client: client,
    timeout: timeout,
  );
}

Future<Map<String, dynamic>> invokeSenderDraft(
  String operation,
  Map<String, dynamic> data, {
  required String idToken,
  required String appCheckToken,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse('$senderDraftServiceUrl/$operation'),
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
      throw const SenderDraftApiException(
        'INTERNAL',
        'Draft service returned an invalid response.',
      );
    }
    if (response.statusCode != 200) {
      final error = payload['error'] as Map?;
      throw SenderDraftApiException(
        '${error?['status'] ?? 'INTERNAL'}',
        '${error?['message'] ?? 'Draft request failed.'}',
      );
    }
    final result = payload['result'];
    if (result is! Map) {
      throw const SenderDraftApiException(
        'INTERNAL',
        'Draft service returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(result);
  } finally {
    if (ownsClient) transport.close();
  }
}
