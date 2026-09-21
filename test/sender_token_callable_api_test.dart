import 'dart:convert';

import 'package:circum/app/send_package/repo/token_callable_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sender adapter sends callable auth envelope', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'result': {'ok': true}}), 200);
    });
    final result = await invokeTokenCallable(
      'updateSenderPushToken',
      {'fcmToken': 'token-1'},
      idToken: 'firebase-id-token',
      client: client,
    );
    expect(result, {'ok': true});
    expect(captured.headers['authorization'], 'Bearer firebase-id-token');
    expect(jsonDecode(captured.body), {'data': {'fcmToken': 'token-1'}});
  });

  test('sender account bootstrap uses the Cloud Run callable envelope', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'result': {'ok': true, 'allowed': true}
        }),
        200,
      );
    });
    final result = await invokeTokenCallable(
      'ensureSenderAccount',
      const {},
      idToken: 'firebase-id-token',
      client: client,
    );
    expect(result, {'ok': true, 'allowed': true});
    expect(captured.url.toString(),
        '$tokenCallableServiceUrl/ensureSenderAccount');
    expect(captured.headers['authorization'], 'Bearer firebase-id-token');
    expect(jsonDecode(captured.body), {'data': {}});
  });

  test('sender adapter preserves callable-compatible errors', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': {
              'status': 'FAILED_PRECONDITION',
              'message': 'Legacy direct-token Rider notifications are disabled.'
            }
          }),
          400,
        ));
    await expectLater(
      invokeTokenCallable(
        'sendRiderUpdate',
        const {},
        idToken: 'firebase-id-token',
        client: client,
      ),
      throwsA(isA<TokenCallableException>().having(
          (error) => error.status, 'status', 'FAILED_PRECONDITION')),
    );
  });
}
