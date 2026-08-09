import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/website/shared/circum_website_app.dart',
  ).readAsStringSync();

  test('Website Rider jobs use the authenticated server projection only', () {
    final riderPortalStart = source.indexOf(
      'class _RiderEnrollmentPortalState',
    );
    final riderPortalEnd = source.indexOf(
      'class _RiderWorkspace',
      riderPortalStart,
    );
    expect(riderPortalStart, greaterThanOrEqualTo(0));
    expect(riderPortalEnd, greaterThan(riderPortalStart));
    final riderPortal = source.substring(riderPortalStart, riderPortalEnd);

    expect(riderPortal, contains("httpsCallable('getAvailableRequests')"));
    expect(riderPortal, contains("jobs('nearestRequests')"));
    expect(riderPortal, contains("jobs('activeJobs')"));
    expect(riderPortal, contains("jobs('completedJobs')"));
    expect(riderPortal, isNot(contains("collection('deliveryRequests')")));
    expect(riderPortal, isNot(contains('_isLiveRiderOffer')));
    expect(riderPortal, isNot(contains('RiderDispatchPolicy.canViewJob')));
  });

  test('Website Rider card presents approved earnings, not customer pricing',
      () {
    final cardStart = source.indexOf('class _DriverJobCard');
    final cardEnd = source.indexOf('class _JobInfoLine', cardStart);
    final card = source.substring(cardStart, cardEnd);

    expect(card, contains("label: 'Rider earnings'"));
    expect(card, isNot(contains("job['pricingBreakdown']")));
    expect(card, isNot(contains("label: 'Price'")));
  });
}
