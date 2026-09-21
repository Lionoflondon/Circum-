import 'dart:convert';

import 'package:circum/website/shared/account_bootstrap_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('account bootstrap uses Cloud Run callable envelope and auth', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'result': {'ok': true}}), 200);
    });

    final result = await invokeAccountBootstrap(
      'ensureSenderAccount',
      const {},
      idToken: 'auth-token',
      client: client,
    );

    expect(result['ok'], isTrue);
    expect(captured.url.host, contains('circum-account-bootstrap'));
    expect(captured.headers['authorization'], 'Bearer auth-token');
    expect(jsonDecode(captured.body), {'data': {}});
  });

  test('Rider App Check header is forwarded', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'result': {'ok': true}}), 200);
    });

    await invokeAccountBootstrap(
      'verifyRiderAccountAccess',
      const {},
      idToken: 'auth-token',
      appCheckToken: 'app-check-token',
      client: client,
    );

    expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
  });

  test('structured account errors are preserved', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': {
              'status': 'PERMISSION_DENIED',
              'message': 'Wrong Circum product.',
            },
          }),
          403,
        ));

    await expectLater(
      invokeAccountBootstrap(
        'ensureSenderAccount',
        const {},
        idToken: 'auth-token',
        client: client,
      ),
      throwsA(isA<AccountBootstrapException>()),
    );
  });
}

