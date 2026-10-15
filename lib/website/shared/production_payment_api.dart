import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';

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
    'sender_qa': 'https://circum-qa-special-flow-j2b7cicfwq-uc.a.run.app',
  };

  static Future<Map<String, dynamic>> call(
    String family,
    String route,
    Map<String, dynamic> data, {
    bool callable = true,
  }) async {
    final origin = _origins[family];
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final appCheckToken = await FirebaseAppCheck.instance.getToken();
    if (origin == null) throw ArgumentError.value(family, 'family');
    return invokeWebsiteProductionPayment(
      Uri.parse('$origin/$route'),
      data,
      idToken: token,
      appCheckToken: appCheckToken,
      callable: callable,
    );
  }
}

/// Sends once: an interrupted write must be reconciled before retrying.
Future<Map<String, dynamic>> invokeWebsiteProductionPayment(
  Uri uri,
  Map<String, dynamic> data, {
  required String? idToken,
  required String? appCheckToken,
  bool callable = true,
  http.Client? client,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final token = idToken;
  if (token == null ||
      token.isEmpty ||
      appCheckToken == null ||
      appCheckToken.isEmpty) {
    throw StateError('payment_auth_required');
  }
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'X-Firebase-AppCheck': appCheckToken,
          },
          body: jsonEncode(callable ? {'data': data} : data),
        )
        .timeout(timeout);
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw StateError('Payment could not be confirmed. Check its status before trying again.');
    }
    if (decoded is! Map<String, dynamic> ||
        response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded.containsKey('error')) {
      throw StateError('Payment could not be confirmed. Check its status before trying again.');
    }
    final Object? result = callable
        ? (decoded.containsKey('result') ? decoded['result'] : decoded['data'])
        : decoded;
    if (result is! Map<String, dynamic> ||
        result.isEmpty ||
        result.containsKey('error') ||
        result['success'] == false ||
        result['ok'] == false) {
      throw StateError('Payment could not be confirmed. Check its status before trying again.');
    }
    return result;
  } on TimeoutException {
    throw StateError('Payment could not be confirmed. Check its status before trying again.');
  } on http.ClientException {
    throw StateError('Payment could not be confirmed. Check its status before trying again.');
  } finally {
    if (client == null) transport.close();
  }
}
