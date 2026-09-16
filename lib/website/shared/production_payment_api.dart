import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class WebsiteProductionPaymentApi {
  const WebsiteProductionPaymentApi._();

  static const _origins = <String, String>{
    'health_plus':
        'https://circum-health-plus-payments-j2b7cicfwq-uc.a.run.app',
    'business_invoices':
        'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app',
    'gifts': 'https://circum-gift-payments-j2b7cicfwq-uc.a.run.app',
    'tips': 'https://circum-tip-payments-j2b7cicfwq-uc.a.run.app',
    'delivery_adjustments':
        'https://circum-delivery-adjustment-payments-j2b7cicfwq-uc.a.run.app',
    'sender_cancellation':
        'https://circum-sender-cancellation-requests-j2b7cicfwq-uc.a.run.app',
    'rider_payouts': 'https://circum-rider-payouts-j2b7cicfwq-uc.a.run.app',
  };

  static Future<Map<String, dynamic>> call(
    String family,
    String route,
    Map<String, dynamic> data, {
    bool callable = true,
  }) async {
    final origin = _origins[family];
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (origin == null || token == null) {
      throw StateError('payment_auth_required');
    }
    final response = await http
        .post(
          Uri.parse('$origin/$route'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(callable ? {'data': data} : data),
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
