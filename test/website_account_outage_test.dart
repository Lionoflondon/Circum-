import 'dart:async';
import 'dart:convert';
import 'package:circum/website/shared/account_bootstrap_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final validResults = <String, Map<String, dynamic>>{
    'website bootstrap': {'allowed': true},
    'website rider application': {'applicationId': 'r1', 'status': 'submitted'}
  };
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
      (200, '{"result":{}}', 'INTERNAL'),
      (200, '{"result":{"ok":false}}', 'INTERNAL'),
      (
        200,
        '{"result":{"ok":"true","allowed":"true","status":"unknown"}}',
        'INTERNAL'
      ),
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
      pending.complete(
          http.Response(jsonEncode({'result': validResults[route.key]}), 200));
      await tester.pump();
    });
    test('${route.key} preserves a valid confirmation', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode({'result': validResults[route.key]}), 200));
      expect(await route.value(client), validResults[route.key]);
    });
  }
  final contracts = <String, List<Map<String, dynamic>>>{
    'ensureSenderAccount': [
      {'allowed': false},
      {'allowed': true}
    ],
    'updateSenderNotificationState': [
      {'ok': true}
    ],
    'verifyRiderAccountAccess': [
      {'ok': true, 'profileExists': false}
    ],
    'updateRiderProfile': [
      {'ok': true}
    ],
    'submitRiderApplication': [
      {'applicationId': 'r1', 'status': 'submitted'},
      {'applicationId': 'r1', 'status': 'under_review', 'idempotent': true},
      {'applicationId': 'r1', 'status': 'suspended'},
    ],
    'sendCircumVerificationEmail': [
      {'ok': true, 'queued': true},
      {'ok': true, 'alreadyVerified': true},
    ],
    'getSenderWallet': [
      {'balance': 0},
      {'balance': 12.5}
    ],
    'listSenderPaymentMethods': [
      {'paymentMethods': []},
      {
        'paymentMethods': [
          {'id': 'pm1'}
        ]
      },
    ],
  };
  for (final contract in contracts.entries) {
    for (final result in contract.value) {
      test('${contract.key} preserves authoritative outcome $result', () async {
        final client = MockClient(
            (_) async => http.Response(jsonEncode({'result': result}), 200));
        expect(
            await invokeAccountBootstrap(contract.key, const {},
                idToken: 'auth', client: client),
            result);
      });
    }
    for (final invalid in <Map<String, dynamic>>[
      {},
      {'unrelated': true},
      {'ok': false},
      {
        'allowed': 'true',
        'ok': 'true',
        'balance': '0',
        'paymentMethods': {},
        'applicationId': 123,
        'status': 'submitted'
      },
    ]) {
      test('${contract.key} rejects unconfirmed map $invalid', () async {
        var attempts = 0;
        final client = MockClient((_) async {
          attempts++;
          return http.Response(jsonEncode({'result': invalid}), 200);
        });
        await expectLater(
            invokeAccountBootstrap(contract.key, const {},
                idToken: 'auth', client: client),
            throwsA(isA<AccountBootstrapException>()));
        expect(attempts, 1);
      });
    }
  }
  for (final invalid in [
    {'applicationId': 'r1', 'status': 'not-a-status'},
    {'applicationId': '', 'status': 'submitted'},
  ]) {
    test('application rejects invalid identity or state $invalid', () async {
      final client = MockClient(
          (_) async => http.Response(jsonEncode({'result': invalid}), 200));
      await expectLater(
          invokeAccountBootstrap('submitRiderApplication', const {},
              idToken: 'auth', client: client),
          throwsA(isA<AccountBootstrapException>()));
    });
  }
}
