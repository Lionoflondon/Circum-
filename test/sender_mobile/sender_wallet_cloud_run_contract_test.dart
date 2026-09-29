import 'dart:convert';

import 'package:circum/app/sender_mobile/sender_wallet_cloud_run_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
}
