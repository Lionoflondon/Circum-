import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/helper/password_recovery.dart';

void main() {
  for (final application in ['sender', 'rider']) {
    test(
        '$application signed-out request uses App Check and only one backend path',
        () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.path, '/requestCircumPasswordReset');
        expect(request.headers['x-firebase-appcheck'], 'attestation');
        expect(request.headers.containsKey('authorization'), false);
        expect(jsonDecode(request.body), {
          'data': {'email': 'account@example.com', 'client': application}
        });
        return http.Response('{"result":{"ok":true}}', 200);
      });
      await requestCircumPasswordReset(
          email: ' Account@example.com ',
          application: application,
          getAppCheckToken: () async => 'attestation',
          client: client);
      expect(calls, 1);
    });
  }
  test('missing or failed App Check prevents any recovery request', () async {
    for (final getToken in [
      () async => null,
      () async => throw StateError('private-token')
    ]) {
      await expectLater(
          requestCircumPasswordReset(
              email: 'account@example.com',
              application: 'sender',
              getAppCheckToken: getToken,
              client: MockClient((_) async => fail('Unexpected HTTP request'))),
          throwsA(isA<PasswordRecoveryException>()));
    }
  });
  test('malformed addresses and unknown app names never reach backend',
      () async {
    for (final input in [
      ('bad', 'sender'),
      ('a@example.com', 'https://evil.test')
    ]) {
      await expectLater(
          requestCircumPasswordReset(
              email: input.$1,
              application: input.$2,
              getAppCheckToken: () async => fail('Unexpected attestation')),
          throwsA(isA<PasswordRecoveryException>()));
    }
  });
  for (final response in [
    http.Response('{"result":{"ok":false}}', 200),
    http.Response('{"result":{"queued":true}}', 200),
    http.Response('private backend detail', 500),
    http.Response('{}', 429)
  ]) {
    test(
        'failure ${response.statusCode} is bounded, safe and never falls back to Firebase mail',
        () async {
      var calls = 0;
      await expectLater(
          requestCircumPasswordReset(
              email: 'account@example.com',
              application: 'sender',
              getAppCheckToken: () async => 'attestation',
              client: MockClient((_) async {
                calls++;
                return response;
              })),
          throwsA(isA<PasswordRecoveryException>().having((e) => e.message,
              'safe message', isNot(contains('private backend detail')))));
      expect(calls, 1);
    });
  }
}
