import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Only these reviewed operations use standalone Cloud Run. No legacy fallback.
const businessHealthCallableUrls = <String, String>{
  'ensureBusinessCompanyCode':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/ensureBusinessCompanyCode',
  'lookupBusinessByCompanyCode':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/lookupBusinessByCompanyCode',
  'requestBusinessAccess':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/requestBusinessAccess',
  'reviewBusinessAccessRequest':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/reviewBusinessAccessRequest',
  'updateBusinessProfile':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/updateBusinessProfile',
  'inviteBusinessMember':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/inviteBusinessMember',
  'updateBusinessMemberRole':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/updateBusinessMemberRole',
  'updateBusinessMemberStatus':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/updateBusinessMemberStatus',
  'removeBusinessMember':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/removeBusinessMember',
  'recordBusinessIrisMoment':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/recordBusinessIrisMoment',
  'createHealthPlusBooking':
      'https://circum-health-plus-payments-j2b7cicfwq-uc.a.run.app/createHealthPlusBooking',
  'updateSenderHealthPlusBooking':
      'https://circum-health-plus-payments-j2b7cicfwq-uc.a.run.app/updateSenderHealthPlusBooking',
  'adminUpdateBusinessMember':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/adminUpdateBusinessMember',
  'createBusinessInvoiceCheckout':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/createBusinessInvoiceCheckout',
  'cancelBusinessInvoiceCheckout':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/cancelBusinessInvoiceCheckout',
  'createBusinessRothCheckout':
      'https://circum-business-roth-checkout-j2b7cicfwq-uc.a.run.app/',
  'adminCreateBusinessInvoice':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/adminCreateBusinessInvoice',
  'listBusinessRothTransactions':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/listBusinessRothTransactions',
  'adminUpdateBusinessAccountStatus':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/adminUpdateBusinessAccountStatus',
  'adminUpdateBusinessOperation':
      'https://circum-business-invoice-payments-j2b7cicfwq-uc.a.run.app/adminUpdateBusinessOperation',
  'adminUpdateHealthPlusPickup':
      'https://circum-health-plus-payments-j2b7cicfwq-uc.a.run.app/adminUpdateHealthPlusPickup',
  'adminUpdateHealthPlusProfile':
      'https://circum-health-plus-payments-j2b7cicfwq-uc.a.run.app/adminUpdateHealthPlusProfile',
  'adminUpdateHealthPlusSchedule':
      'https://circum-health-plus-payments-j2b7cicfwq-uc.a.run.app/adminUpdateHealthPlusSchedule',
  'updateHealthPlusPickupStatus':
      'https://circum-health-plus-payments-j2b7cicfwq-uc.a.run.app/updateHealthPlusPickupStatus',
};
const _requiresAppCheck = <String>{
  'adminUpdateBusinessMember',
  'createBusinessRothCheckout',
  'adminCreateBusinessInvoice',
  'listBusinessRothTransactions',
  'adminUpdateBusinessAccountStatus',
  'adminUpdateBusinessOperation',
  'adminUpdateHealthPlusPickup',
  'adminUpdateHealthPlusProfile',
  'adminUpdateHealthPlusSchedule',
};

class BusinessHealthCallableResult<T> {
  const BusinessHealthCallableResult(this.data);
  final T data;
}

extension BusinessHealthCallableTransport on FirebaseFunctions {
  BusinessHealthCallable businessHealthCallable(String name) =>
      BusinessHealthCallable(name);
}

class BusinessHealthCallable {
  BusinessHealthCallable(this.name) {
    if (!businessHealthCallableUrls.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'Unsupported operation');
    }
  }
  final String name;
  Future<BusinessHealthCallableResult<T>> call<T>([
    Map<String, dynamic> data = const {},
  ]) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw FirebaseFunctionsException(
          code: 'unauthenticated', message: 'Sign in to continue.');
    }
    final appCheck = await FirebaseAppCheck.instance.getToken();
    final result = await invokeBusinessHealthCallable(
      name,
      data,
      idToken: token,
      appCheckToken: appCheck,
    );
    return BusinessHealthCallableResult<T>(result as T);
  }
}

Future<dynamic> invokeBusinessHealthCallable(
  String name,
  Map<String, dynamic> data, {
  required String? idToken,
  String? appCheckToken,
  http.Client? client,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final url = businessHealthCallableUrls[name];
  if (url == null) {
    throw ArgumentError.value(name, 'name', 'Unsupported operation');
  }
  if (idToken == null || idToken.isEmpty) {
    throw FirebaseFunctionsException(
        code: 'unauthenticated', message: 'Sign in to continue.');
  }
  if (_requiresAppCheck.contains(name) &&
      (appCheckToken == null || appCheckToken.isEmpty)) {
    throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Security verification is required.');
  }
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
            if (appCheckToken != null && appCheckToken.isNotEmpty)
              'X-Firebase-AppCheck': appCheckToken
          },
          body: jsonEncode(
              name == 'updateHealthPlusPickupStatus' ? data : {'data': data}),
        )
        .timeout(timeout);
    dynamic payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw FirebaseFunctionsException(
          code: response.statusCode >= 500 ? 'unavailable' : 'internal',
          message:
              'The service could not complete the request. Check its status before retrying.');
    }
    if (payload is! Map) {
      throw FirebaseFunctionsException(
          code: 'internal', message: 'Invalid service response.');
    }
    if (payload.containsKey('error') ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      final error = payload['error'];
      final status = error is Map ? error['status'] ?? error['code'] : null;
      final code =
          '${status ?? (response.statusCode == 401 ? 'UNAUTHENTICATED' : response.statusCode == 403 ? 'PERMISSION_DENIED' : response.statusCode >= 500 ? 'UNAVAILABLE' : 'INTERNAL')}'
              .toLowerCase()
              .replaceAll('_', '-');
      throw FirebaseFunctionsException(
          code: code,
          message: error is Map
              ? '${error['message'] ?? 'Request failed.'}'
              : '${payload['message'] ?? error ?? 'Request failed.'}',
          details: error is Map ? error['details'] : null);
    }
    if (payload.containsKey('result')) return payload['result'];
    if (payload.containsKey('data')) return payload['data'];
    if (name == 'updateHealthPlusPickupStatus') {
      return Map<String, dynamic>.from(payload);
    }
    throw FirebaseFunctionsException(
        code: 'internal', message: 'Missing callable result.');
  } on TimeoutException {
    // An upstream action may have completed. Never retry or fall back automatically.
    throw FirebaseFunctionsException(
        code: 'deadline-exceeded',
        message: 'The request timed out. Check its status before retrying.');
  } on http.ClientException {
    throw FirebaseFunctionsException(
        code: 'unavailable',
        message:
            'Connection interrupted. Check the request status before retrying.');
  } finally {
    if (ownsClient) transport.close();
  }
}
