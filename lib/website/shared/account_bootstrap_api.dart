import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const accountBootstrapServiceUrl =
    'https://circum-account-bootstrap-516426305461.us-central1.run.app';

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
  const senderAppCheckOperations = {
    'updateSenderNotificationState',
    'sendCircumVerificationEmail',
  };
  const senderWalletReadOperations = {
    'getSenderWallet',
    'listSenderPaymentMethods',
  };
  if (operation != 'ensureSenderAccount' &&
      !riderOperations.contains(operation) &&
      !senderAppCheckOperations.contains(operation) &&
      !senderWalletReadOperations.contains(operation)) {
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
      senderAppCheckOperations.contains(operation) ||
      senderWalletReadOperations.contains(operation)) {
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
    return _decodeAccountResponse(response, operation);
  } on TimeoutException {
    throw const AccountBootstrapException(
      'DEADLINE_EXCEEDED',
      'Confirmation took too long. Check its status before trying again.',
    );
  } on http.ClientException {
    throw const AccountBootstrapException(
      'UNAVAILABLE',
      'Connection interrupted. Check its status before trying again.',
    );
  } finally {
    if (ownsClient) transport.close();
  }
}

Map<String, dynamic> _decodeAccountResponse(
    http.Response response, String operation) {
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
    throw AccountBootstrapException(fallbackStatus, fallbackMessage);
  }
  if (decoded is! Map<String, dynamic>) {
    throw AccountBootstrapException(fallbackStatus, fallbackMessage);
  }
  if (response.statusCode != 200 || decoded.containsKey('error')) {
    final error = decoded['error'];
    throw AccountBootstrapException(
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
    throw const AccountBootstrapException('INTERNAL', fallbackMessage);
  }
  // Validate the outcome used by the caller, not just its JSON envelope.
  final confirmed = switch (operation) {
    'ensureSenderAccount' => result['allowed'] is bool,
    'verifyRiderAccountAccess' ||
    'updateRiderProfile' ||
    'updateSenderNotificationState' =>
      result['ok'] == true,
    'submitRiderApplication' => result['applicationId'] is String &&
        (result['applicationId'] as String).trim().isNotEmpty &&
        const {
          'submitted',
          'resubmitted',
          'under_review',
          'approved',
          'suspended',
          'archived'
        }.contains(result['status']),
    'sendCircumVerificationEmail' => result['ok'] == true &&
        (result['queued'] == true || result['alreadyVerified'] == true),
    'getSenderWallet' =>
      result['balance'] is num && (result['balance'] as num).isFinite,
    'listSenderPaymentMethods' => result['paymentMethods'] is List &&
        (result['paymentMethods'] as List).every((method) =>
            method is Map &&
            method['id'] is String &&
            (method['id'] as String).isNotEmpty),
    _ => false,
  };
  if (!confirmed) {
    throw const AccountBootstrapException('INTERNAL', fallbackMessage);
  }
  return result;
}
