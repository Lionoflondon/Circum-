import 'dart:convert';
import 'dart:io';

import 'package:circum/app/admin/admin_access_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Admin access adapter sends Auth, App Check and callable envelope',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'result': {
            'roles': ['super_admin'],
            'permissions': ['*'],
            'accessGranted': true,
          },
        }),
        200,
      );
    });

    final result = await invokeAdminAccess(
      idToken: 'firebase-id-token',
      appCheckToken: 'app-check-token',
      client: client,
    );

    expect(result['accessGranted'], isTrue);
    expect(captured.url.host, contains('circum-admin-access'));
    expect(captured.url.path, '/adminResolveAccess');
    expect(captured.headers['authorization'], 'Bearer firebase-id-token');
    expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
    expect(jsonDecode(captured.body), {'data': <String, dynamic>{}});
  });

  test('Admin access adapter preserves safe server error classes', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': {
              'status': 'PERMISSION_DENIED',
              'message': 'private details must not be rendered',
            },
          }),
          403,
        ));

    await expectLater(
      invokeAdminAccess(
        idToken: 'firebase-id-token',
        appCheckToken: 'app-check-token',
        client: client,
      ),
      throwsA(isA<AdminAccessException>().having(
        (error) => error.status,
        'status',
        'PERMISSION_DENIED',
      )),
    );
  });

  test(
      'Admin source has one Cloud Run access caller and retains restore dedupe',
      () {
    final source =
        File('lib/app/admin/admin_phase1_shell.dart').readAsStringSync();
    expect(source, contains('callAdminAccess(auth: _auth)'));
    expect(source, isNot(contains("httpsCallable('adminResolveAccess')")));
    expect(source,
        contains('if (pending != null && _restoreUid == uid) return pending;'));
  });
}
