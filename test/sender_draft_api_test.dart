import 'dart:convert';

import 'package:circum/app/sender_mobile/sender_draft_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Sender draft transport uses the Cloud Run callable envelope', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'result': {'ok': true, 'revision': 1}}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await invokeSenderDraft(
      'saveSenderDraft',
      {'schemaVersion': 1, 'baseRevision': 0},
      idToken: 'id-token',
      appCheckToken: 'app-check-token',
      client: client,
    );

    expect(result['revision'], 1);
    expect(captured.url.host, contains('circum-sender-drafts'));
    expect(captured.url.path, '/saveSenderDraft');
    expect(captured.headers['authorization'], 'Bearer id-token');
    expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
    expect(jsonDecode(captured.body), {
      'data': {'schemaVersion': 1, 'baseRevision': 0},
    });
  });

  test('Sender draft transport preserves structured conflicts', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': {
              'status': 'ABORTED',
              'message': 'Your draft was updated on another device.',
            },
          }),
          409,
        ));

    await expectLater(
      invokeSenderDraft(
        'saveSenderDraft',
        const {},
        idToken: 'id-token',
        appCheckToken: 'app-check-token',
        client: client,
      ),
      throwsA(isA<SenderDraftApiException>().having(
        (error) => error.status,
        'status',
        'ABORTED',
      )),
    );
  });

  test('client source contains no provider credential', () {
    expect(senderDraftServiceUrl, isNot(contains('AIza')));
    expect(senderDraftServiceUrl, isNot(contains('STRIPE')));
  });
}
