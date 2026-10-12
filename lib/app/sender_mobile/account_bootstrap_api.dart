import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
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

Future<Map<String, dynamic>> updateSenderNotificationStateViaCloudRun({
  required String action,
  required Iterable<String> notificationIds,
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
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
  final appCheckToken =
      await (appCheck ?? FirebaseAppCheck.instance).getToken();
  if (appCheckToken == null || appCheckToken.isEmpty) {
    throw const SenderAccountBootstrapException(
      'FAILED_PRECONDITION',
      'Circum security verification is required.',
    );
  }
  return invokeSenderNotificationState(
    action: action,
    notificationIds: notificationIds,
    idToken: idToken,
    appCheckToken: appCheckToken,
    client: client,
  );
}

Future<Map<String, dynamic>> invokeSenderNotificationState({
  required String action,
  required Iterable<String> notificationIds,
  required String idToken,
  required String appCheckToken,
  http.Client? client,
}) async {
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse(
            '$senderAccountBootstrapServiceUrl/updateSenderNotificationState',
          ),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $idToken',
            'x-firebase-appcheck': appCheckToken,
          },
          body: jsonEncode({
            'data': {
              'action': action,
              'notificationIds': notificationIds.toList(growable: false),
            },
          }),
        )
        .timeout(const Duration(seconds: 8));
    return _decodeAccountResponse(response);
  } on TimeoutException {
    throw const SenderAccountBootstrapException(
      'DEADLINE_EXCEEDED',
      'Confirmation took too long. Check its status before trying again.',
    );
  } on http.ClientException {
    throw const SenderAccountBootstrapException(
      'UNAVAILABLE',
      'Connection interrupted. Check its status before trying again.',
    );
  } finally {
    if (ownsClient) transport.close();
  }
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
    return _decodeAccountResponse(response);
  } on TimeoutException {
    throw const SenderAccountBootstrapException(
      'DEADLINE_EXCEEDED',
      'Confirmation took too long. Check its status before trying again.',
    );
  } on http.ClientException {
    throw const SenderAccountBootstrapException(
      'UNAVAILABLE',
      'Connection interrupted. Check its status before trying again.',
    );
  } finally {
    if (ownsClient) transport.close();
  }
}

Future<Map<String, dynamic>> sendSenderVerificationEmailViaCloudRun({
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  http.Client? client,
}) async {
  final idToken =
      await (auth ?? FirebaseAuth.instance).currentUser?.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const SenderAccountBootstrapException(
        'UNAUTHENTICATED', 'Sign in to continue.');
  }
  final appCheckToken =
      await (appCheck ?? FirebaseAppCheck.instance).getToken();
  if (appCheckToken == null || appCheckToken.isEmpty) {
    throw const SenderAccountBootstrapException(
        'FAILED_PRECONDITION', 'Circum security verification is required.');
  }
  return invokeSenderVerificationEmailViaCloudRun(
      idToken: idToken, appCheckToken: appCheckToken, client: client);
}

Future<Map<String, dynamic>> invokeSenderVerificationEmailViaCloudRun({
  required String idToken,
  required String appCheckToken,
  http.Client? client,
}) async {
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
            Uri.parse(
                '$senderAccountBootstrapServiceUrl/sendCircumVerificationEmail'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $idToken',
              'x-firebase-appcheck': appCheckToken,
            },
            body: jsonEncode({'data': {}}))
        .timeout(const Duration(seconds: 15));
    return _decodeAccountResponse(response);
  } on TimeoutException {
    throw const SenderAccountBootstrapException(
      'DEADLINE_EXCEEDED',
      'Confirmation took too long. Check its status before trying again.',
    );
  } on http.ClientException {
    throw const SenderAccountBootstrapException(
      'UNAVAILABLE',
      'Connection interrupted. Check its status before trying again.',
    );
  } finally {
    if (client == null) transport.close();
  }
}

Map<String, dynamic> _decodeAccountResponse(http.Response response) {
  final fallbackStatus = switch (response.statusCode) {
    401 => 'UNAUTHENTICATED',
    403 => 'PERMISSION_DENIED',
    429 => 'RESOURCE_EXHAUSTED',
    >= 500 => 'UNAVAILABLE',
    _ => 'INTERNAL',
  };
  const fallbackMessage =
      'The service could not confirm this request. Check its status before trying again.';
  Object? decoded;
  try {
    decoded = jsonDecode(response.body);
  } on FormatException {
    throw SenderAccountBootstrapException(fallbackStatus, fallbackMessage);
  }
  if (decoded is! Map<String, dynamic>) {
    throw SenderAccountBootstrapException(fallbackStatus, fallbackMessage);
  }
  if (response.statusCode != 200 || decoded.containsKey('error')) {
    final error = decoded['error'];
    throw SenderAccountBootstrapException(
      error is Map && error['status'] is String
          ? error['status'] as String
          : fallbackStatus,
      error is Map && error['message'] is String
          ? error['message'] as String
          : fallbackMessage,
    );
  }
  final result = decoded['result'];
  if (result is! Map<String, dynamic>) {
    throw const SenderAccountBootstrapException('INTERNAL', fallbackMessage);
  }
  return result;
}
