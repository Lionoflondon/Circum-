import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Admin payout actions use the isolated live payout owner', () {
    final shell = File(
      'lib/app/admin/admin_phase1_shell.dart',
    ).readAsStringSync();
    final api = File(
      'lib/app/admin/admin_production_payment_api.dart',
    ).readAsStringSync();

    expect(
      shell,
      contains(
        "AdminProductionPaymentApi.call(\n          'createRiderTransferOrPayout'",
      ),
    );
    expect(
      shell,
      contains(
        "AdminProductionPaymentApi.call(\n          'adminReviewRiderWithdrawal'",
      ),
    );
    expect(
      shell,
      isNot(contains("httpsCallable('createRiderTransferOrPayout')")),
    );
    expect(
      shell,
      isNot(contains("httpsCallable('adminReviewRiderWithdrawal')")),
    );
    expect(api, contains('circum-rider-payouts-j2b7cicfwq-uc.a.run.app'));
  });
}
