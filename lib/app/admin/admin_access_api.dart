import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const adminAccessServiceUrl =
    'https://circum-admin-access-516426305461.us-central1.run.app';
const _adminCallableRoutes = {
  'adminResolveAccess',
  'adminQueryPage',
  'adminSaveGiftRequestEditor',
};

class AdminAccessException implements Exception {
  const AdminAccessException(this.status, this.message);

  final String status;
  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> callAdminAccess({
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  http.Client? client,
}) async {
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  final idToken = await user?.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const AdminAccessException('UNAUTHENTICATED', 'Sign in to continue.');
  }
  final appCheckToken =
      await (appCheck ?? FirebaseAppCheck.instance).getToken();
  if (appCheckToken == null || appCheckToken.isEmpty) {
    throw const AdminAccessException(
      'FAILED_PRECONDITION',
      'Circum security verification is required.',
    );
  }
  return invokeAdminAccess(
    idToken: idToken,
    appCheckToken: appCheckToken,
    client: client,
  );
}

Future<Map<String, dynamic>> invokeAdminAccess({
  required String idToken,
  required String appCheckToken,
  http.Client? client,
}) async {
  return invokeAdminCallable(
    route: 'adminResolveAccess',
    data: const <String, dynamic>{},
    idToken: idToken,
    appCheckToken: appCheckToken,
    client: client,
  );
}

Future<Map<String, dynamic>> invokeAdminCallable({
  required String route,
  required Map<String, dynamic> data,
  required String idToken,
  required String appCheckToken,
  http.Client? client,
}) async {
  if (!_adminCallableRoutes.contains(route)) {
    throw ArgumentError.value(route, 'route', 'Unsupported Admin API route.');
  }
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse('$adminAccessServiceUrl/$route'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $idToken',
            'x-firebase-appcheck': appCheckToken,
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(const Duration(seconds: 20));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = payload['error'] as Map?;
      throw AdminAccessException(
        '${error?['status'] ?? 'INTERNAL'}',
        '${error?['message'] ?? 'Admin access request failed.'}',
      );
    }
    return Map<String, dynamic>.from(payload['result'] as Map);
  } finally {
    if (ownsClient) transport.close();
  }
}
