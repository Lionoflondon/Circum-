import 'dart:convert';
import 'dart:io';

import 'package:circum/website/shared/account_bootstrap_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('current website and Sender source contain no failed callable routes',
      () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in sources) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains("httpsCallable('ensureSenderAccount')")),
          reason: file.path);
      expect(source, isNot(contains("httpsCallable('updateRiderProfile')")),
          reason: file.path);
    }
  });

  test('account bootstrap uses Cloud Run callable envelope and auth', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
          jsonEncode({
            'result': {'ok': true}
          }),
          200);
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
      return http.Response(
          jsonEncode({
            'result': {'ok': true}
          }),
          200);
    });

    final result = await invokeAccountBootstrap(
      'updateRiderProfile',
      const {'fullName': 'Rider'},
      idToken: 'auth-token',
      appCheckToken: 'app-check-token',
      client: client,
    );

    expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
    expect(captured.headers['authorization'], 'Bearer auth-token');
    expect(jsonDecode(captured.body), {
      'data': {'fullName': 'Rider'},
    });
    expect(result, {'ok': true});
  });

  test('Rider application submission uses authenticated Cloud Run callable',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'result': {'applicationId': 'rider-1', 'status': 'submitted'},
        }),
        200,
      );
    });

    final result = await invokeAccountBootstrap(
      'submitRiderApplication',
      const {'idempotencyKey': 'website-rider-application:rider-1'},
      idToken: 'auth-token',
      appCheckToken: 'app-check-token',
      client: client,
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/submitRiderApplication');
    expect(captured.headers['authorization'], 'Bearer auth-token');
    expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
    expect(jsonDecode(captured.body), {
      'data': {'idempotencyKey': 'website-rider-application:rider-1'},
    });
    expect(result, {'applicationId': 'rider-1', 'status': 'submitted'});
  });

  test('Rider Website application caller no longer invokes the Gen 1 callable',
      () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    expect(source, contains("callAccountBootstrap('submitRiderApplication'"));
    expect(source, isNot(contains("httpsCallable('submitRiderApplication')")));
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
