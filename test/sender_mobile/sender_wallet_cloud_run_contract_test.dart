import 'dart:convert';

import 'package:circum/app/sender_mobile/sender_wallet_cloud_run_api.dart';
import 'package:circum/app/sender_mobile/sender_referral_cloud_run_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Sender referrals use the authenticated Cloud Run route', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'result': {
            'referralCode': 'QA1234',
            'referralLink': 'https://circumuk.com/join/QA1234',
          },
        }),
        200,
      );
    });

    final result = await invokeSenderReferralCodeViaCloudRun(
      idToken: 'auth-token',
      appCheckToken: 'app-check-token',
      client: client,
    );

    expect(result['referralCode'], 'QA1234');
    expect(captured.url.host, contains('circum-referral-callables'));
    expect(captured.url.path, '/v1/callable/ensureReferralCode');
    expect(captured.headers['authorization'], 'Bearer auth-token');
    expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
  });
  test(
    'Sender Wallet activity uses the authenticated Cloud Run route',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'result': {
              'transactions': const [],
              'nextPageToken': 'cursor-2',
              'source': 'walletId',
            },
          }),
          200,
        );
      });

      final result = await invokeSenderWalletTransactionsViaCloudRun(
        idToken: 'auth-token',
        appCheckToken: 'app-check-token',
        pageToken: 'cursor-1',
        pageSize: 20,
        client: client,
      );

      expect(result['nextPageToken'], 'cursor-2');
      expect(captured.url.host, contains('circum-account-bootstrap'));
      expect(captured.url.path, '/getSenderWalletTransactions');
      expect(captured.headers['authorization'], 'Bearer auth-token');
      expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
      expect(jsonDecode(captured.body), {
        'data': {'pageSize': 20, 'pageToken': 'cursor-1'},
      });
    },
  );

  test('Sender Wallet activity preserves safe structured failures', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'status': 'UNAUTHENTICATED',
            'message': 'Sign in to continue.',
          },
        }),
        401,
      ),
    );

    await expectLater(
      invokeSenderWalletTransactionsViaCloudRun(
        idToken: 'expired-token',
        appCheckToken: 'app-check-token',
        client: client,
      ),
      throwsA(
        isA<SenderWalletCloudRunException>().having(
          (error) => error.status,
          'status',
          'UNAUTHENTICATED',
        ),
      ),
    );
  });

  test('fresh Wallet balance uses the authenticated account Cloud Run owner',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'result': {
            'balance': 12.5,
            'currency': 'ROTH',
            'status': 'active',
            'updatedAt': '2026-09-29T09:00:00.000Z',
          },
        }),
        200,
      );
    });

    final result = await invokeSenderWalletOperationViaCloudRun(
      operation: 'getSenderWallet',
      fallbackMessage: 'balance unavailable',
      idToken: 'auth-token',
      appCheckToken: 'app-check-token',
      client: client,
    );

    expect(result['balance'], 12.5);
    expect(captured.url.path, '/getSenderWallet');
    expect(captured.headers['authorization'], 'Bearer auth-token');
    expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
  });

  test(
      'payment-method list uses the same protected owner and preserves the empty state',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'result': {
            'customerId': null,
            'defaultPaymentMethodId': null,
            'preference': 'ask_every_checkout',
            'paymentMethods': const [],
          },
        }),
        200,
      );
    });

    final result = await invokeSenderWalletOperationViaCloudRun(
      operation: 'listSenderPaymentMethods',
      fallbackMessage: 'payment methods unavailable',
      idToken: 'auth-token',
      appCheckToken: 'app-check-token',
      client: client,
    );

    expect(result['paymentMethods'], isEmpty);
    expect(captured.url.path, '/listSenderPaymentMethods');
  });
}
