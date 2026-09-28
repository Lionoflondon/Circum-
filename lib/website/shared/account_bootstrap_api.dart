import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const accountBootstrapServiceUrl =
    'https://circum-account-bootstrap-j2b7cicfwq-uc.a.run.app';

class AccountBootstrapException implements Exception {
  const AccountBootstrapException(this.status, this.message);

  final String status;
  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> callAccountBootstrap(
  String operation,
  Map<String, dynamic> data, {
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  http.Client? client,
}) async {
  const riderOperations = {
    'verifyRiderAccountAccess',
    'updateRiderProfile',
    'submitRiderApplication',
  };
  const senderProfileOperations = {
    'updateSenderProfile',
    'updateSenderProfilePhoto',
    'updateSenderPreferences',
    'revokeSenderSessions',
    'getSenderAccountActivity',
    'exportSenderData',
    'requestSenderEmailChange',
    'closeCircumAccount',
  };
  if (operation != 'ensureSenderAccount' &&
      !riderOperations.contains(operation) &&
      !senderProfileOperations.contains(operation)) {
    throw ArgumentError.value(operation, 'operation', 'Unsupported operation');
  }
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  final idToken = await user?.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const AccountBootstrapException(
      'UNAUTHENTICATED',
      'Sign in to continue.',
    );
  }
  String? appCheckToken;
  if (riderOperations.contains(operation) ||
      senderProfileOperations.contains(operation)) {
    appCheckToken = await (appCheck ?? FirebaseAppCheck.instance).getToken();
    if (appCheckToken == null || appCheckToken.isEmpty) {
      throw const AccountBootstrapException(
        'FAILED_PRECONDITION',
        'Circum security verification is required.',
      );
    }
  }
  return invokeAccountBootstrap(
    operation,
    data,
    idToken: idToken,
    appCheckToken: appCheckToken,
    client: client,
  );
}

Future<Map<String, dynamic>> invokeAccountBootstrap(
  String operation,
  Map<String, dynamic> data, {
  required String idToken,
  String? appCheckToken,
  http.Client? client,
}) async {
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse('$accountBootstrapServiceUrl/$operation'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $idToken',
            if (appCheckToken != null) 'x-firebase-appcheck': appCheckToken,
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(const Duration(seconds: 25));
    late final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const AccountBootstrapException(
        'INTERNAL',
        'Account service returned an invalid response.',
      );
    }
    if (response.statusCode != 200) {
      final error = payload['error'] as Map?;
      throw AccountBootstrapException(
        '${error?['status'] ?? 'INTERNAL'}',
        '${error?['message'] ?? 'Account request failed.'}',
      );
    }
    final result = payload['result'];
    if (result is! Map) {
      throw const AccountBootstrapException(
        'INTERNAL',
        'Account service returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(result);
  } finally {
    if (ownsClient) transport.close();
  }
}
