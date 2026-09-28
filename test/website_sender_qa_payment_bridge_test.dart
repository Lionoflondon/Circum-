import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final web = File(
    'lib/website/shared/circum_website_app.dart',
  ).readAsStringSync();
  final paymentApi = File(
    'lib/website/shared/production_payment_api.dart',
  ).readAsStringSync();

  test('Sender Web discovers the trusted QA payment capability', () {
    expect(web, contains("'sender_capability'"));
    expect(web, contains("'sender_quote'"));
    expect(web, contains("'sender_payment_session'"));
    expect(web, contains("'sender_finalize'"));
    expect(web, contains('qaRothEnabled'));
    expect(
      web,
      contains('circum-sender-delivery-payments-j2b7cicfwq-uc.a.run.app'),
    );
    expect(web, isNot(contains('senderQaFixtureId')));
  });

  test('Sender Web QA calls use the private App Check payment transport', () {
    expect(paymentApi, contains("'sender_qa':"));
    expect(
      paymentApi,
      contains('circum-qa-special-flow-j2b7cicfwq-uc.a.run.app'),
    );
    expect(paymentApi, contains('X-Firebase-AppCheck'));
    expect(paymentApi, contains('Authorization'));
  });
}
