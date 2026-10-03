import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

class AdminProductionPaymentApi {
  const AdminProductionPaymentApi._();

  static const _riderPayoutOrigin =
      'https://circum-rider-payouts-j2b7cicfwq-uc.a.run.app';

  static const _riderConnectOrigin =
      'https://circum-rider-connect-accounts-j2b7cicfwq-uc.a.run.app';
  static const _connectRoutes = {
    'createStripeConnectAccountForRider',
    'createStripeOnboardingLink',
    'refreshStripeOnboardingLink',
    'syncStripeConnectStatus',
    'createStripeAccountManagementLink',
  };

  static Future<Map<String, dynamic>> call(
    String route,
    Map<String, dynamic> data,
  ) async {
    final origin =
        _connectRoutes.contains(route) ? _riderConnectOrigin : _riderPayoutOrigin;
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final appCheckToken = await FirebaseAppCheck.instance.getToken();
    if (token == null || appCheckToken == null || appCheckToken.isEmpty) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Authentication and App Check are required.',
      );
    }
    final response = await http
        .post(
          Uri.parse('$origin/$route'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'X-Firebase-AppCheck': appCheckToken,
          },
          body: jsonEncode({'data': data}),
        )
        .timeout(const Duration(seconds: 30));
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final message = error is Map ? error['message'] : decoded['message'];
      final status = error is Map
          ? '${error['status'] ?? 'INTERNAL'}'
          : 'INTERNAL';
      throw FirebaseFunctionsException(
        code: status.toLowerCase().replaceAll('_', '-'),
        message: '${message ?? error ?? 'payment_request_failed'}',
        details: error is Map ? error['details'] : null,
      );
    }
    final result = decoded['result'] ?? decoded['data'] ?? decoded;
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }
}
