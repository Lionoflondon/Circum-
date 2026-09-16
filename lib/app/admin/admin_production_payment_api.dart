import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AdminProductionPaymentApi {
  const AdminProductionPaymentApi._();

  static const _riderPayoutOrigin =
      'https://circum-rider-payouts-j2b7cicfwq-uc.a.run.app';

  static Future<Map<String, dynamic>> call(
    String route,
    Map<String, dynamic> data,
  ) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw StateError('payment_auth_required');
    final response = await http
        .post(
          Uri.parse('$_riderPayoutOrigin/$route'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
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
      throw StateError('${message ?? error ?? 'payment_request_failed'}');
    }
    final result = decoded['result'] ?? decoded['data'] ?? decoded;
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }
}
