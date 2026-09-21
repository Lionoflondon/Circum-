import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const senderAccountBootstrapServiceUrl =
    'https://circum-account-bootstrap-516426305461.us-central1.run.app';

class SenderAccountBootstrapException implements Exception {
  const SenderAccountBootstrapException(this.status, this.message);

  final String status;
  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> ensureSenderAccountViaCloudRun({
  FirebaseAuth? auth,
  http.Client? client,
}) async {
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  final idToken = await user?.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const SenderAccountBootstrapException(
      'UNAUTHENTICATED',
      'Sign in to continue.',
    );
  }
  return invokeSenderAccountBootstrap(idToken: idToken, client: client);
}

Future<Map<String, dynamic>> invokeSenderAccountBootstrap({
  required String idToken,
  http.Client? client,
}) async {
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse(
            '$senderAccountBootstrapServiceUrl/ensureSenderAccount',
          ),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $idToken',
          },
          body: jsonEncode({'data': <String, dynamic>{}}),
        )
        .timeout(const Duration(seconds: 8));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = payload['error'] as Map?;
      throw SenderAccountBootstrapException(
        '${error?['status'] ?? 'INTERNAL'}',
        '${error?['message'] ?? 'Account request failed.'}',
      );
    }
    return Map<String, dynamic>.from(payload['result'] as Map);
  } finally {
    if (ownsClient) transport.close();
  }
}

