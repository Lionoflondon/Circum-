import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const senderAccountBootstrapServiceUrl =
    'https://circum-account-bootstrap-j2b7cicfwq-uc.a.run.app';

class SenderAccountBootstrapException implements Exception {
  const SenderAccountBootstrapException(this.status, this.message);

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
  Duration timeout = const Duration(seconds: 20),
}) async {
  const appCheckOperations = {
    'updateSenderProfile',
    'updateSenderProfilePhoto',
    'updateSenderPreferences',
    'revokeSenderSessions',
    'getSenderAccountActivity',
    'exportSenderData',
    'requestSenderEmailChange',
    'closeCircumAccount',
  };
  const operations = {
    'ensureSenderAccount',
    ...appCheckOperations,
  };
  if (!operations.contains(operation)) {
    throw ArgumentError.value(
      operation,
      'operation',
      'Unsupported account bootstrap operation',
    );
  }
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  final idToken = await user?.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const SenderAccountBootstrapException(
      'UNAUTHENTICATED',
      'Sign in to continue.',
    );
  }
  String? appCheckToken;
  if (appCheckOperations.contains(operation)) {
    appCheckToken = await (appCheck ?? FirebaseAppCheck.instance).getToken();
    if (appCheckToken == null || appCheckToken.isEmpty) {
      throw const SenderAccountBootstrapException(
        'FAILED_PRECONDITION',
        'Circum security verification is required.',
      );
    }
  }
  return _invokeAccountBootstrapOperation(
    operation,
    data,
    idToken: idToken,
    appCheckToken: appCheckToken,
    client: client,
    timeout: timeout,
  );
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

Future<Map<String, dynamic>> _invokeAccountBootstrapOperation(
  String operation,
  Map<String, dynamic> data, {
  required String idToken,
  String? appCheckToken,
  http.Client? client,
  required Duration timeout,
}) async {
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse('$senderAccountBootstrapServiceUrl/$operation'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $idToken',
            if (appCheckToken != null) 'x-firebase-appcheck': appCheckToken,
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(timeout);
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const SenderAccountBootstrapException(
        'INTERNAL',
        'Account service returned an invalid response.',
      );
    }
    if (response.statusCode != 200) {
      final error = payload['error'] as Map?;
      throw SenderAccountBootstrapException(
        '${error?['status'] ?? 'INTERNAL'}',
        '${error?['message'] ?? 'Account request failed.'}',
      );
    }
    final result = payload['result'];
    if (result is! Map) {
      throw const SenderAccountBootstrapException(
        'INTERNAL',
        'Account service returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(result);
  } finally {
    if (ownsClient) transport.close();
  }
}
