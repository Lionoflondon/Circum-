import 'dart:async';
import 'package:circum/website/shared/account_bootstrap_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final routes = <String, Future<Map<String, dynamic>> Function(http.Client)>{
    'website bootstrap': (client) => invokeAccountBootstrap(
        'ensureSenderAccount', const {},
        idToken: 'auth', client: client),
    'website rider application': (client) => invokeAccountBootstrap(
        'submitRiderApplication', const {},
        idToken: 'auth', appCheckToken: 'check', client: client),
  };
  for (final route in routes.entries) {
    for (final response in [
      (500, 'Billing is disabled', 'UNAVAILABLE'),
      (503, '<html>Service unavailable</html>', 'UNAVAILABLE'),
      (502, '[]', 'UNAVAILABLE'),
      (401, 'Unauthorized', 'UNAUTHENTICATED'),
      (403, '<html>Forbidden</html>', 'PERMISSION_DENIED'),
      (429, '', 'RESOURCE_EXHAUSTED'),
      (200, '{}', 'INTERNAL'),
      (200, '{"result":null}', 'INTERNAL'),
      (200, '{"result":[]}', 'INTERNAL'),
      (200, '{"result":true}', 'INTERNAL'),
      (200, '[]', 'INTERNAL'),
      (200, '<html>proxy</html>', 'INTERNAL'),
      (
        200,
        '{"error":{"status":"PERMISSION_DENIED","message":"Access denied"},"result":{"ok":true}}',
        'PERMISSION_DENIED'
      ),
      (400, '{"error":"bad request"}', 'INTERNAL'),
    ]) {
      test('${route.key} rejects ${response.$1} ${response.$2}', () async {
        var attempts = 0;
        final client = MockClient((_) async {
          attempts++;
          return http.Response(response.$2, response.$1);
        });
        await expectLater(
            route.value(client),
            throwsA(isA<AccountBootstrapException>()
                .having((e) => e.status, 'status', response.$3)));
        expect(attempts, 1,
            reason: 'An unconfirmed write must not be replayed.');
      });
    }
    test('${route.key} maps an interrupted connection', () async {
      var attempts = 0;
      final client = MockClient((_) async {
        attempts++;
        throw http.ClientException('internal transport details');
      });
      await expectLater(
          route.value(client),
          throwsA(isA<AccountBootstrapException>()
              .having((e) => e.status, 'status', 'UNAVAILABLE')
              .having((e) => e.message, 'message',
                  isNot(contains('internal transport details')))));
      expect(attempts, 1);
    });
    testWidgets('${route.key} bounds a request that never completes',
        (tester) async {
      var attempts = 0;
      final pending = Completer<http.Response>();
      final client = MockClient((_) {
        attempts++;
        return pending.future;
      });
      final check = expectLater(
          route.value(client),
          throwsA(isA<AccountBootstrapException>()
              .having((e) => e.status, 'status', 'DEADLINE_EXCEEDED')));
      await tester.pump(const Duration(seconds: 31));
      await check;
      expect(attempts, 1);
      pending.complete(http.Response('{"result":{"ok":true}}', 200));
      await tester.pump();
    });
    test('${route.key} preserves a valid confirmation', () async {
      final client =
          MockClient((_) async => http.Response('{"result":{"ok":true}}', 200));
      expect(await route.value(client), {'ok': true});
    });
  }
}
