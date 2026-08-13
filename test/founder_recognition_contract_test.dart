import 'dart:io';

import 'package:circum/app/business/business_models.dart';
import 'package:circum/app/sender_profile/sender_profile.dart';
import 'package:circum/website/shared/policies/driver_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Rider Founder recognition is separate from rank and Trust Points', () {
    final profile = DriverProfile.fromMap('founder-rider', {
      'fullName': 'Founder Rider',
      'rank': 'veteran',
      'trustPoints': 3,
      'recognitions': {
        'founder': {'awarded': true, 'number': 1},
      },
    });

    expect(profile.isFounder, isTrue);
    expect(profile.founderNumber, 1);
    expect(profile.rank, 'veteran');
  });

  test('Founding Rider cohort does not receive personal Founder recognition',
      () {
    final profile = DriverProfile.fromMap('ordinary-rider', {
      'fullName': 'Ordinary Rider',
      'rank': 'veteran',
      'trustPoints': 999,
      'isFoundingRider': true,
      'recognitions': {
        'foundingRider': {'awarded': true, 'number': 44},
      },
    });

    expect(profile.isFounder, isFalse);
    expect(profile.founderNumber, isNull);
    expect(profile.isFoundingRider, isTrue);
    expect(profile.foundingRiderNumber, 44);
    expect(profile.rank, 'veteran');
  });

  test('Sender founder account presents as Legend, not Founder', () {
    final profile = SenderProfile.fromMap('sender-1', {
      'fullName': 'Legend Sender',
      'recognitions': {
        'legend': {'awarded': true, 'number': 7},
      },
    });

    expect(profile.isLegend, isTrue);
    expect(profile.legendNumber, 7);
  });

  test('Business founder account presents as Patron, not role authority', () {
    final account = BusinessAccount.fromMap('business-1', {
      'businessName': 'Circum Business',
      'status': 'pending',
      'recognitions': {
        'patron': {'awarded': true, 'number': 2},
      },
    });

    expect(account.isPatron, isTrue);
    expect(account.patronNumber, 2);
    expect(account.isApproved, isFalse);
  });

  test(
      'shared UI keeps Founder on Rider profile and away from Sender rider card',
      () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    final riderProfileStart = source.indexOf('class _RiderOrderProfileCard');
    final riderProfileEnd = source.indexOf('enum _RiderPortalTab');
    final senderRiderStart = source.indexOf('class _RiderRankPresentation');
    final senderRiderEnd = source.indexOf('class _DriverRatingPrompt');

    expect(riderProfileStart, isNonNegative);
    expect(riderProfileEnd, greaterThan(riderProfileStart));
    final riderProfileSource =
        source.substring(riderProfileStart, riderProfileEnd);
    expect(riderProfileSource, contains('_FounderRecognitionBadge'));
    expect(riderProfileSource, contains('_riderProfileHasFounderRecognition'));
    expect(riderProfileSource, contains('_circumOrderRankForBackendProfile'));
    expect(
        riderProfileSource, isNot(contains('_circumOrderRankForPerformance')));

    expect(senderRiderStart, isNonNegative);
    expect(senderRiderEnd, greaterThan(senderRiderStart));
    final senderRiderSource =
        source.substring(senderRiderStart, senderRiderEnd);
    expect(senderRiderSource, isNot(contains('_FounderRecognitionBadge')));
    expect(senderRiderSource, isNot(contains('FOUNDER')));
  });
}
