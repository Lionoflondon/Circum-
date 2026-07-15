import 'dart:io';

import 'package:circum/app/send_package/view/ratings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rating titles follow the five canonical levels', () {
    expect(deliveryRatingTitle(5), 'Outstanding Delivery');
    expect(deliveryRatingTitle(4), 'Great Delivery');
    expect(deliveryRatingTitle(3), 'Good Delivery');
    expect(deliveryRatingTitle(2), 'Needs Improvement');
    expect(deliveryRatingTitle(1), 'Poor Experience');
  });

  test('Apple Pay and Google Pay are platform-specific', () {
    expect(ratingMethodVisible('apple_pay', TargetPlatform.iOS), isTrue);
    expect(ratingMethodVisible('apple_pay', TargetPlatform.android), isFalse);
    expect(ratingMethodVisible('google_pay', TargetPlatform.android), isTrue);
    expect(ratingMethodVisible('google_pay', TargetPlatform.iOS), isFalse);
    expect(ratingMethodVisible('saved_card', TargetPlatform.iOS), isTrue);
  });

  test('feedback suggestions use the approved customer-facing set', () {
    expect(ratingFeedbackChoices, [
      'Friendly',
      'Professional',
      'Fast',
      'Excellent Communication',
      'Careful Handling',
    ]);
  });

  test('Sender appreciation uses canonical callables and PaymentSheet', () {
    final source =
        File('lib/app/send_package/view/ratings.dart').readAsStringSync();
    expect(source, contains("httpsCallable('submitDeliveryRating')"));
    expect(source, contains("httpsCallable('submitDeliveryTip')"));
    expect(source, contains('Stripe.instance.presentPaymentSheet()'));
    expect(source, contains('Submit Appreciation'));
    expect(source, contains('100% of your tip goes directly to your rider.'));
    expect(source, isNot(contains("collection('driverRatings').doc")));
    expect(source, isNot(contains("collection('deliveryTips').doc")));
  });

  test('retired RateRider direct history write is absent', () {
    final bloc = File('lib/app/send_package/bloc/send_package_bloc.dart')
        .readAsStringSync();
    final events = File('lib/app/send_package/bloc/send_package_event.dart')
        .readAsStringSync();
    expect(bloc, isNot(contains('_handleRateRider')));
    expect(events, isNot(contains('class RateRider')));
  });
}
