import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/website/shared/circum_website_app.dart',
  ).readAsStringSync();

  test('Rider Web referral UI promises Roth only and loads backend code', () {
    final start = source.indexOf('class _RiderReferralsTab');
    final end = source.indexOf('class _RiderEnrollmentPortal', start);
    final referrals = source.substring(start, end);

    expect(
      referrals,
      contains(
        'Earn 5 Roth when a rider you invite completes their first paid delivery.',
      ),
    );
    expect(referrals, contains("httpsCallable('ensureReferralCode')"));
    expect(referrals, contains("where('referrerUserId'"));
    expect(referrals, contains('Rider referral link copied.'));
    expect(referrals, isNot(contains('£10')));
    expect(referrals, isNot(contains('cash')));
  });
}
