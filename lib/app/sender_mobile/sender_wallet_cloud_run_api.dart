import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const senderWalletTransactionsServiceUrl =
    'https://circum-account-bootstrap-516426305461.us-central1.run.app';
const senderWalletCloudRunServiceUrl = senderWalletTransactionsServiceUrl;

class SenderWalletCloudRunException implements Exception {
  const SenderWalletCloudRunException(this.status, this.message);

  final String status;
  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> loadSenderWalletTransactionsViaCloudRun({
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  String? pageToken,
  int pageSize = 20,
  http.Client? client,
}) async {
  return loadSenderWalletOperationViaCloudRun(
    operation: 'getSenderWalletTransactions',
    fallbackMessage: 'Wallet activity is temporarily unavailable.',
    pageToken: pageToken,
    pageSize: pageSize,
    auth: auth,
    appCheck: appCheck,
    client: client,
  );
}

Future<Map<String, dynamic>> loadSenderWalletViaCloudRun({
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  http.Client? client,
}) =>
    loadSenderWalletOperationViaCloudRun(
      operation: 'getSenderWallet',
      fallbackMessage: 'Your Roth balance is temporarily unavailable.',
      auth: auth,
      appCheck: appCheck,
      client: client,
    );

Future<Map<String, dynamic>> loadSenderPaymentMethodsViaCloudRun({
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  http.Client? client,
}) =>
    loadSenderWalletOperationViaCloudRun(
      operation: 'listSenderPaymentMethods',
      fallbackMessage: 'Payment methods are temporarily unavailable.',
      auth: auth,
      appCheck: appCheck,
      client: client,
    );

Future<Map<String, dynamic>> loadSenderWalletOperationViaCloudRun({
  required String operation,
  required String fallbackMessage,
  FirebaseAuth? auth,
  FirebaseAppCheck? appCheck,
  String? idToken,
  String? appCheckToken,
  String? pageToken,
  int pageSize = 20,
  http.Client? client,
}) async {
  try {
    final user = (auth ?? FirebaseAuth.instance).currentUser;
    final resolvedIdToken = idToken ?? await user?.getIdToken();
    if (resolvedIdToken == null || resolvedIdToken.isEmpty) {
      throw const SenderWalletCloudRunException(
        'UNAUTHENTICATED',
        'Sign in to continue.',
      );
    }
    final resolvedAppCheckToken = appCheckToken ??
        await (appCheck ?? FirebaseAppCheck.instance).getToken();
    if (resolvedAppCheckToken == null || resolvedAppCheckToken.isEmpty) {
      throw const SenderWalletCloudRunException(
        'FAILED_PRECONDITION',
        'Circum security verification is required.',
      );
    }
    return invokeSenderWalletOperationViaCloudRun(
      operation: operation,
      fallbackMessage: fallbackMessage,
      idToken: resolvedIdToken,
      appCheckToken: resolvedAppCheckToken,
      pageToken: pageToken,
      pageSize: pageSize,
      client: client,
    );
  } on SenderWalletCloudRunException {
    rethrow;
  } catch (_) {
    throw SenderWalletCloudRunException('UNAVAILABLE', fallbackMessage);
  }
}

Future<Map<String, dynamic>> invokeSenderWalletTransactionsViaCloudRun({
  required String idToken,
  required String appCheckToken,
  String? pageToken,
  int pageSize = 20,
  http.Client? client,
}) =>
    invokeSenderWalletOperationViaCloudRun(
      operation: 'getSenderWalletTransactions',
      fallbackMessage: 'Wallet activity is temporarily unavailable.',
      idToken: idToken,
      appCheckToken: appCheckToken,
      pageToken: pageToken,
      pageSize: pageSize,
      client: client,
    );

Future<Map<String, dynamic>> invokeSenderWalletOperationViaCloudRun({
  required String operation,
  required String fallbackMessage,
  required String idToken,
  required String appCheckToken,
  String? pageToken,
  int pageSize = 20,
  http.Client? client,
}) async {
  final ownsClient = client == null;
  final transport = client ?? http.Client();
  try {
    final response = await transport
        .post(
          Uri.parse(
            '$senderWalletCloudRunServiceUrl/$operation',
          ),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $idToken',
            'x-firebase-appcheck': appCheckToken,
            'x-circum-correlation-id':
                'sender_wallet_${operation}_${DateTime.now().microsecondsSinceEpoch}',
          },
          body: jsonEncode({
            'data': {'pageSize': pageSize, 'pageToken': pageToken},
          }),
        )
        .timeout(const Duration(seconds: 8));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = payload['error'] as Map?;
      throw SenderWalletCloudRunException(
        '${error?['status'] ?? 'INTERNAL'}',
        '${error?['message'] ?? fallbackMessage}',
      );
    }
    final result = payload['result'];
    if (result is! Map) {
      throw const SenderWalletCloudRunException(
        'INTERNAL',
        'Wallet request returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(result);
  } on SenderWalletCloudRunException {
    rethrow;
  } catch (_) {
    throw const SenderWalletCloudRunException(
      'UNAVAILABLE',
      'Wallet request is temporarily unavailable.',
    );
  } finally {
    if (ownsClient) transport.close();
  }
}
