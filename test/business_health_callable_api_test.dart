import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:circum/app/sender_mobile/business_health_callable_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

TypeMatcher<FirebaseFunctionsException> errorCode(String code) =>
    isA<FirebaseFunctionsException>().having((e) => e.code, 'code', code);
void main() {
  test(
      'all reviewed routes preserve security, idempotency and callable envelope',
      () async {
    expect(businessHealthCallableUrls, hasLength(24));
    for (final entry in businessHealthCallableUrls.entries) {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.toString(), entry.value);
        expect(request.url.host, endsWith('.a.run.app'));
        expect(request.headers['Authorization'], 'Bearer auth');
        expect(request.headers['X-Firebase-AppCheck'], 'appcheck');
        final data = {'idempotencyKey': 'same-claim', 'amount': 0};
        expect(
            jsonDecode(request.body),
            entry.key == 'updateHealthPlusPickupStatus'
                ? data
                : {'data': data});
        return http.Response('{"result":{"amount":0,"paid":false}}', 200);
      });
      final result = await invokeBusinessHealthCallable(
          entry.key, {'idempotencyKey': 'same-claim', 'amount': 0},
          idToken: 'auth', appCheckToken: 'appcheck', client: client);
      expect(result, {'amount': 0, 'paid': false});
      expect(requests, 1);
    }
  });
  test('missing Auth and required App Check never send a request', () async {
    final client =
        MockClient((_) async => throw StateError('must not reach network'));
    await expectLater(
        invokeBusinessHealthCallable('createHealthPlusBooking', {},
            idToken: null, client: client),
        throwsA(errorCode('unauthenticated')));
    await expectLater(
        invokeBusinessHealthCallable('adminCreateBusinessInvoice', {},
            idToken: 'auth', client: client),
        throwsA(errorCode('failed-precondition')));
    await expectLater(
        invokeBusinessHealthCallable('unknown', {},
            idToken: 'auth', client: client),
        throwsArgumentError);
  });
  test('callable role denial preserves code, message and details', () async {
    final client = MockClient((_) async => http.Response(
        '{"error":{"status":"PERMISSION_DENIED","message":"Wrong owner","details":{"role":"sender"}}}',
        403));
    await expectLater(
        invokeBusinessHealthCallable('updateBusinessProfile', {},
            idToken: 'auth', client: client),
        throwsA(errorCode('permission-denied')
            .having((e) => e.message, 'message', 'Wrong owner')
            .having((e) => e.details, 'details', {'role': 'sender'})));
  });
  test('timeout and connection loss never retry a potentially committed action',
      () async {
    for (final timeout in [true, false]) {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        if (timeout) throw TimeoutException('unknown upstream outcome');
        throw http.ClientException('connection lost');
      });
      await expectLater(
          invokeBusinessHealthCallable('createBusinessInvoiceCheckout', {},
              idToken: 'auth', client: client),
          throwsA(errorCode(timeout ? 'deadline-exceeded' : 'unavailable')));
      expect(requests, 1);
    }
  });
  test('provider/runtime HTML is sanitized and never falls back', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('<html>private runtime error</html>', 503);
    });
    await expectLater(
        invokeBusinessHealthCallable('createHealthPlusBooking', {},
            idToken: 'auth', client: client),
        throwsA(errorCode('unavailable')));
    expect(requests, 1);
  });
  test(
      'missing success envelope is rejected while false and null remain valid results',
      () async {
    for (final value in [false, null]) {
      final client = MockClient(
          (_) async => http.Response(jsonEncode({'result': value}), 200));
      expect(
          await invokeBusinessHealthCallable('updateBusinessProfile', {},
              idToken: 'auth', client: client),
          value);
    }
    await expectLater(
        invokeBusinessHealthCallable('updateBusinessProfile', {},
            idToken: 'auth',
            client: MockClient((_) async => http.Response('{}', 200))),
        throwsA(errorCode('internal')));
  });
  test('native callers cannot silently return to the failed SDK routes', () {
    for (final file in [
      'lib/app/business/business_repository.dart',
      'lib/app/health_plus/view/health_plus.dart',
      'lib/app/admin/admin_phase1_shell.dart'
    ]) {
      final source = File(file).readAsStringSync();
      for (final op in businessHealthCallableUrls.keys) {
        expect(source, isNot(contains(".httpsCallable('$op')")),
            reason: '$file $op');
      }
    }
  });
}
