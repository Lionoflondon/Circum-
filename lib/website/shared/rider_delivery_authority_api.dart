import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const riderDeliveryAuthorityServiceUrl =
    'https://circum-rider-delivery-authority-516426305461.us-central1.run.app';

class RiderDeliveryAuthorityException implements Exception {
  const RiderDeliveryAuthorityException(this.status, this.message);

  final String status;
  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> callRiderDeliveryAuthority(
  String operation,
  Map<String, dynamic> data, {
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  http.Client? client,
}) async {
  if (operation != 'completeDelivery' && operation != 'getAvailableRequests') {
    throw ArgumentError.value(operation, 'operation', 'Unsupported operation');
  }
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  final idToken = await user?.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const RiderDeliveryAuthorityException(
      'UNAUTHENTICATED',
      'Sign in to continue.',
    );
  }
  final appCheckToken =
      await (appCheck ?? FirebaseAppCheck.instance).getToken();
  if (appCheckToken == null || appCheckToken.isEmpty) {
    throw const RiderDeliveryAuthorityException(
      'FAILED_PRECONDITION',
      'Circum Rider security verification is required.',
    );
  }
  return invokeRiderDeliveryAuthority(
    operation,
    data,
    idToken: idToken,
    appCheckToken: appCheckToken,
    client: client,
  );
}

Future<Map<String, dynamic>> invokeRiderDeliveryAuthority(
  String operation,
  Map<String, dynamic> data, {
  required String idToken,
  required String appCheckToken,
  http.Client? client,
}) async {
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse('$riderDeliveryAuthorityServiceUrl/$operation'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $idToken',
            'x-firebase-appcheck': appCheckToken,
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(const Duration(seconds: 30));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = payload['error'] as Map?;
      throw RiderDeliveryAuthorityException(
        '${error?['status'] ?? 'INTERNAL'}',
        '${error?['message'] ?? 'Rider delivery request failed.'}',
      );
    }
    return Map<String, dynamic>.from(payload['result'] as Map);
  } finally {
    if (ownsClient) transport.close();
  }
}
