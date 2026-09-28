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
    expect(web, contains("'sender_roth_prepare'"));
    expect(web, contains("'sender_roth_balance'"));
    expect(web, contains('qaRothEnabled'));
    expect(
      web,
      contains('circum-sender-delivery-payments-j2b7cicfwq-uc.a.run.app'),
    );
    expect(web, isNot(contains('senderQaFixtureId')));
  });

  test('Sender Web QA calls use the Firebase-authenticated QA boundary', () {
    expect(paymentApi, contains('FirebaseFunctions.instance'));
    expect(paymentApi, contains('httpsCallable'));
    expect(paymentApi, contains('FirebaseAppCheck.instance.getToken()'));
    expect(paymentApi,
        isNot(contains('circum-qa-special-flow-j2b7cicfwq-uc.a.run.app')));
  });

  test('Sender Web never falls back from a QA bridge failure to live Stripe',
      () {
    expect(web, contains('A failed QA capability check must fail closed'));
    expect(web,
        contains('Never retry this operation against the live payment owner'));
    expect(web, contains('qa_roth_delivery_not_authoritative'));
  });
}
