import 'dart:convert';
import 'dart:io';
import 'package:circum/app/sender_mobile/account_bootstrap_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Sender sends branded verification with Auth and App Check', () async {
    late http.Request request;
    final client = MockClient((r) async {
      request = r;
      return http.Response(
          jsonEncode({
            'result': {'ok': true, 'queued': true}
          }),
          200);
    });
    final result = await invokeSenderVerificationEmailViaCloudRun(
        idToken: 'auth', appCheckToken: 'appcheck', client: client);
    expect(result['queued'], isTrue);
    expect(request.url.path, '/sendCircumVerificationEmail');
    expect(request.headers['authorization'], 'Bearer auth');
    expect(request.headers['x-firebase-appcheck'], 'appcheck');
    expect(jsonDecode(request.body), {'data': {}});
    final source =
        File('lib/app/authentication/bloc/auth_bloc.dart').readAsStringSync();
    expect(source, isNot(contains('sendEmailVerification()')));
    expect(
        source, contains('sendSenderVerificationEmailViaCloudRun(auth: auth)'));
  });
}
