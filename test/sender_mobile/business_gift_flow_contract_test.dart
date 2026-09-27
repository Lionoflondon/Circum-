import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Business Gift uses the canonical order callable and all approved rails',
      () {
    final repository =
        File('lib/app/business/business_repository.dart').readAsStringSync();
    final view =
        File('lib/app/business/business_gift_view.dart').readAsStringSync();
    final business =
        File('lib/app/business/business_view.dart').readAsStringSync();

    expect(repository, contains("httpsCallable('createBusinessGiftOrder')"));
    expect(view, contains("'card'"));
    expect(view, contains("'invoice'"));
    expect(view, contains("'roth'"));
    expect(view, contains('idempotencyKey'));
    expect(view, contains('No duplicate order was created'));
    expect(business,
        isNot(contains(r"_showMessage('Invitation failed: $error')")));
    expect(
        business,
        isNot(contains(
            r"_showMessage('Invoice payment could not start: $error')")));
    expect(business, contains('BusinessGiftView('));
    expect(business, isNot(contains('child: const GiftModeView()')));
  });

  test('self Gift frequency copy matches the canonical four-month interval',
      () {
    final draft = File('lib/app/sender_mobile/gift_journey_draft.dart')
        .readAsStringSync();
    final payment =
        File('lib/app/sender_mobile/gift_payment_view.dart').readAsStringSync();
    expect(draft, contains("'quarterly': 'Every 4 months'"));
    expect(payment, contains("? 'Every 4 months'"));
  });
}
