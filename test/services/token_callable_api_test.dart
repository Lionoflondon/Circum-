import 'dart:convert';

import 'package:circum/services/token_callable_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'adapter sends callable envelope, Firebase auth and Rider App Check',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'result': {'ok': true},
          }),
          200,
        );
      });

      final result = await invokeTokenCallable(
        'updateRiderPushToken',
        {'fcmToken': 'token-1'},
        idToken: 'firebase-id-token',
        appCheckToken: 'app-check-token',
        client: client,
      );

      expect(result, {'ok': true});
      expect(
        captured.url.toString(),
        '$tokenCallableServiceUrl/updateRiderPushToken',
      );
      expect(captured.headers['authorization'], 'Bearer firebase-id-token');
      expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
      expect(jsonDecode(captured.body), {
        'data': {'fcmToken': 'token-1'},
      });
    },
  );

  test(
    'adapter preserves callable-compatible error status and message',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'status': 'FAILED_PRECONDITION',
              'message':
                  'Legacy direct-token Rider notifications are disabled.',
            },
          }),
          400,
        ),
      );

      await expectLater(
        invokeTokenCallable(
          'sendRiderUpdate',
          const {},
          idToken: 'firebase-id-token',
          client: client,
        ),
        throwsA(
          isA<TokenCallableException>()
              .having((error) => error.status, 'status', 'FAILED_PRECONDITION')
              .having(
                (error) => error.message,
                'message',
                'Legacy direct-token Rider notifications are disabled.',
              ),
        ),
      );
    },
  );
}
