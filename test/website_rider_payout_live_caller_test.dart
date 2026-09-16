import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Rider web withdrawal uses the isolated live payout owner', () {
    final website = File(
      'lib/website/shared/circum_website_app.dart',
    ).readAsStringSync();
    final api = File(
      'lib/website/shared/production_payment_api.dart',
    ).readAsStringSync();

    expect(
      website,
      contains("WebsiteProductionPaymentApi.call(\n        'rider_payouts'"),
    );
    expect(
      website,
      isNot(contains("httpsCallable('requestRiderWithdrawal')")),
    );
    expect(api, contains('circum-rider-payouts-j2b7cicfwq-uc.a.run.app'));
  });
}
