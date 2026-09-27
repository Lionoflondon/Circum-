import 'dart:convert';

import 'package:circum/app/send_package/repo/iris_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('IRIS transport sends Auth, App Check and callable payload', () async {
    final client = MockClient((request) async {
      expect(request.url.host, contains('circum-iris'));
      expect(request.url.path, '/analyseIris');
      expect(request.headers['authorization'], 'Bearer auth');
      expect(request.headers['x-firebase-appcheck'], 'check');
      expect(jsonDecode(request.body)['data']['description'], 'weed');
      return http.Response(
        jsonEncode({
          'result': {
            'compliance': {'status': 'prohibited'},
          },
        }),
        200,
      );
    });
    final result = await invokeIris(
      'analyseIris',
      {'description': 'weed'},
      idToken: 'auth',
      appCheckToken: 'check',
      client: client,
    );
    expect((result['compliance'] as Map)['status'], 'prohibited');
  });

  test('IRIS transport preserves safe failure copy', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'status': 'FAILED_PRECONDITION',
            'message': 'Circum security verification is required.',
          },
        }),
        400,
      ),
    );
    await expectLater(
      invokeIris(
        'analyseIris',
        {},
        idToken: 'auth',
        appCheckToken: 'check',
        client: client,
      ),
      throwsA(
        isA<IrisApiException>().having(
          (exception) => exception.status,
          'status',
          'FAILED_PRECONDITION',
        ),
      ),
    );
  });
}
