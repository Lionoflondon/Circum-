import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const addressPlacesServiceUrl =
    'https://circum-address-places-516426305461.us-central1.run.app';

class AddressPlacesException implements Exception {
  const AddressPlacesException(this.status, this.message);

  final String status;
  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> callAddressPlaces(
  String operation,
  Map<String, dynamic> data, {
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  http.Client? client,
}) async {
  if (!const {
    'searchFreeUkAddresses',
    'resolveUkAddressPlace',
  }.contains(operation)) {
    throw ArgumentError.value(operation, 'operation', 'Unsupported operation');
  }
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  final idToken = await user?.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const AddressPlacesException(
      'UNAUTHENTICATED',
      'Sign in to continue.',
    );
  }
  final appCheckToken = await (appCheck ?? FirebaseAppCheck.instance)
      .getToken();
  if (appCheckToken == null || appCheckToken.isEmpty) {
    throw const AddressPlacesException(
      'FAILED_PRECONDITION',
      'Circum security verification is required.',
    );
  }
  return invokeAddressPlaces(
    operation,
    data,
    idToken: idToken,
    appCheckToken: appCheckToken,
    client: client,
  );
}

Future<Map<String, dynamic>> invokeAddressPlaces(
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
          Uri.parse('$addressPlacesServiceUrl/$operation'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $idToken',
            'x-firebase-appcheck': appCheckToken,
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(const Duration(seconds: 8));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = payload['error'] as Map?;
      throw AddressPlacesException(
        '${error?['status'] ?? 'INTERNAL'}',
        '${error?['message'] ?? 'Address request failed.'}',
      );
    }
    return Map<String, dynamic>.from(payload['result'] as Map);
  } finally {
    if (ownsClient) transport.close();
  }
}

