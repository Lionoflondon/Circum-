import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const tokenCallableServiceUrl =
    'https://circum-token-callables-516426305461.us-central1.run.app';

class TokenCallableException implements Exception {
  const TokenCallableException(this.status, this.message);

  final String status;
  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> callTokenCallable(
  String name,
  Map<String, dynamic> data, {
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  http.Client? client,
}) async {
  if (!const {
    'ensureSenderAccount',
    'updateSenderPushToken',
    'updateRiderPushToken',
    'sendRiderUpdate',
  }.contains(name)) {
    throw ArgumentError.value(name, 'name', 'Unsupported token callable');
  }
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  final idToken = await user?.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const TokenCallableException(
      'UNAUTHENTICATED',
      'Sign in to continue.',
    );
  }
  String? appCheckToken;
  if (name == 'updateRiderPushToken') {
    appCheckToken = await (appCheck ?? FirebaseAppCheck.instance).getToken();
    if (appCheckToken == null || appCheckToken.isEmpty) {
      throw const TokenCallableException(
        'FAILED_PRECONDITION',
        'Circum Rider security verification is required.',
      );
    }
  }
  return invokeTokenCallable(
    name,
    data,
    idToken: idToken,
    appCheckToken: appCheckToken,
    client: client,
  );
}

Future<Map<String, dynamic>> invokeTokenCallable(
  String name,
  Map<String, dynamic> data, {
  required String idToken,
  String? appCheckToken,
  http.Client? client,
}) async {
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final response = await transport.post(
      Uri.parse('$tokenCallableServiceUrl/$name'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $idToken',
        if (appCheckToken != null) 'x-firebase-appcheck': appCheckToken,
      },
      body: jsonEncode({'data': data}),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = payload['error'] as Map?;
      throw TokenCallableException(
        '${error?['status'] ?? 'INTERNAL'}',
        '${error?['message'] ?? 'Token request failed.'}',
      );
    }
    return Map<String, dynamic>.from(payload['result'] as Map);
  } finally {
    if (ownsClient) transport.close();
  }
}
