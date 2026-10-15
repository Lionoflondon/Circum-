import 'dart:async';
import 'dart:convert';
import 'package:circum/website/shared/production_payment_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final uri = Uri.parse('https://payments.invalid/test');
  Future<Map<String, dynamic>> call(
    http.Client client, {
    String? token = 'auth',
    String? appCheck = 'app-check',
    bool callable = true,
    Duration timeout = const Duration(seconds: 1),
  }) =>
      invokeWebsiteProductionPayment(uri, {'paymentId': 'stable-id'},
          idToken: token,
          appCheckToken: appCheck,
          client: client,
          callable: callable,
          timeout: timeout);

  test('authenticated callable and direct response contracts succeed',
      () async {
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer auth');
      expect(request.headers['X-Firebase-AppCheck'], 'app-check');
      expect(jsonDecode(request.body), {
        'data': {'paymentId': 'stable-id'}
      });
      return http.Response('{"result":{"status":"pending"}}', 200);
    });
    expect(await call(client), {'status': 'pending'});
    expect(
        await call(
            MockClient((_) async => http.Response('{"data":{"id":"p"}}', 200))),
        {'id': 'p'});
    expect(
        await call(
            MockClient((_) async => http.Response('{"status":"pending"}', 200)),
            callable: false),
        {'status': 'pending'});
  });

  for (final body in [
    '',
    '<html>Outage</html>',
    'null',
    '[]',
    '{}',
    '{"result":null}',
    '{"result":[]}',
    '{"result":{}}',
    '{"error":{"message":"denied"}}',
    '{"error":null,"result":{"id":"p"}}',
    '{"result":{"error":"denied"}}',
    '{"result":{"success":false}}',
    '{"result":{"ok":false}}',
    '{"id":"unwrapped"}'
  ]) {
    test('unconfirmed response fails closed: $body', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response(body, 200);
      });
      await expectLater(call(client), throwsStateError);
      expect(requests, 1);
    });
  }
  for (final status in [302, 401, 403, 429, 500, 503]) {
    test('HTTP $status cannot confirm payment', () async {
      await expectLater(
          call(MockClient(
              (_) async => http.Response('{"result":{"id":"p"}}', status))),
          throwsStateError);
    });
  }
  test('missing authentication or App Check sends no request', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    await expectLater(call(client, token: null), throwsStateError);
    await expectLater(call(client, token: ''), throwsStateError);
    await expectLater(call(client, appCheck: null), throwsStateError);
    await expectLater(call(client, appCheck: ''), throwsStateError);
    expect(requests, 0);
  });
  test('timeouts and connection loss are never replayed', () async {
    for (final timeoutCase in [true, false]) {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        if (timeoutCase) return Completer<http.Response>().future;
        throw http.ClientException('connection lost');
      });
      await expectLater(call(client, timeout: const Duration(milliseconds: 5)),
          throwsStateError);
      expect(requests, 1);
    }
  });
}
