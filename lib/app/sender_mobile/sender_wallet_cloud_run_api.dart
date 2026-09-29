import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const senderWalletTransactionsServiceUrl =
    'https://circum-account-bootstrap-516426305461.us-central1.run.app';

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
  final user = (auth ?? FirebaseAuth.instance).currentUser;
  final idToken = await user?.getIdToken();
  if (idToken == null || idToken.isEmpty) {
    throw const SenderWalletCloudRunException(
      'UNAUTHENTICATED',
      'Sign in to continue.',
    );
  }
  final appCheckToken = await (appCheck ?? FirebaseAppCheck.instance)
      .getToken();
  if (appCheckToken == null || appCheckToken.isEmpty) {
    throw const SenderWalletCloudRunException(
      'FAILED_PRECONDITION',
      'Circum security verification is required.',
    );
  }
  return invokeSenderWalletTransactionsViaCloudRun(
    idToken: idToken,
    appCheckToken: appCheckToken,
    pageToken: pageToken,
    pageSize: pageSize,
    client: client,
  );
}

Future<Map<String, dynamic>> invokeSenderWalletTransactionsViaCloudRun({
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
            '$senderWalletTransactionsServiceUrl/getSenderWalletTransactions',
          ),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $idToken',
            'x-firebase-appcheck': appCheckToken,
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
        '${error?['message'] ?? 'Wallet activity is temporarily unavailable.'}',
      );
    }
    final result = payload['result'];
    if (result is! Map) {
      throw const SenderWalletCloudRunException(
        'INTERNAL',
        'Wallet activity returned an invalid response.',
      );
    }
    return Map<String, dynamic>.from(result);
  } on SenderWalletCloudRunException {
    rethrow;
  } catch (_) {
    throw const SenderWalletCloudRunException(
      'UNAVAILABLE',
      'Wallet activity is temporarily unavailable.',
    );
  } finally {
    if (ownsClient) transport.close();
  }
}
