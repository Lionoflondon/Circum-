import 'dart:convert';

import 'package:circum/app/sender_mobile/account_bootstrap_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Sender account bootstrap uses Cloud Run and callable envelope',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'result': {'ok': true, 'allowed': true}}),
        200,
      );
    });

    final result = await invokeSenderAccountBootstrap(
      idToken: 'auth-token',
      client: client,
    );

    expect(result['allowed'], isTrue);
    expect(captured.url.host, contains('circum-account-bootstrap'));
    expect(captured.url.path, '/ensureSenderAccount');
    expect(captured.headers['authorization'], 'Bearer auth-token');
    expect(jsonDecode(captured.body), {'data': {}});
  });

  test('Sender account bootstrap preserves structured errors', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': {
              'status': 'PERMISSION_DENIED',
              'message': 'This account cannot access Sender.',
            },
          }),
          403,
        ));

    await expectLater(
      invokeSenderAccountBootstrap(idToken: 'auth-token', client: client),
      throwsA(isA<SenderAccountBootstrapException>()),
    );
  });
}

