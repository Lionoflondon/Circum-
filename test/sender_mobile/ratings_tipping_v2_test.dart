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

  test('Sender Web rating submission uses backend callables', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    final submitStart = source.indexOf('Future<void> _submitDriverRating()');
    final submitEnd = source.indexOf('void _listenToChat', submitStart);
    expect(submitStart, isNonNegative);
    expect(submitEnd, greaterThan(submitStart));
    final submitSource = source.substring(submitStart, submitEnd);

    expect(submitSource, contains("httpsCallable('submitDeliveryRating')"));
    expect(submitSource, contains("httpsCallable('submitDeliveryTip')"));
    expect(submitSource, isNot(contains("collection('driverRatings')")));
    expect(
      submitSource,
      isNot(contains("collection('riderWalletTransactions')")),
    );
    expect(submitSource, isNot(contains("collection('riderEarnings')")));
    expect(source, isNot(contains('_recalculateDriverPerformance')));
  });

  test('legacy web Rider acceptance uses the canonical callable', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    final acceptStart = source.indexOf('Future<void> _acceptDeliveryJob');
    final acceptEnd =
        source.indexOf('void _syncRiderLiveLocationPublishing', acceptStart);
    expect(acceptStart, isNonNegative);
    expect(acceptEnd, greaterThan(acceptStart));
    final acceptSource = source.substring(acceptStart, acceptEnd);

    expect(acceptSource, contains("httpsCallable('acceptRideRequests')"));
    expect(acceptSource, isNot(contains("collection('deliveryRequests')")));
    expect(acceptSource, isNot(contains("collection('chats')")));
    expect(acceptSource, isNot(contains("'status': 'accepted'")));
  });

  test('legacy web Rider lifecycle uses canonical delivery callables', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    final statusStart = source.indexOf('Future<void> _updateAcceptedJobStatus');
    final statusEnd = source.indexOf(
      'Future<Map<String, dynamic>?> _collectVanguardPinVerification',
      statusStart,
    );
    expect(statusStart, isNonNegative);
    expect(statusEnd, greaterThan(statusStart));
    final statusSource = source.substring(statusStart, statusEnd);

    expect(
      statusSource,
      contains("httpsCallable('updateDeliveryTrackingStatus')"),
    );
    expect(statusSource, isNot(contains("collection('deliveryRequests')")));
    expect(statusSource, isNot(contains("collection('riderEarnings')")));
    expect(
      statusSource,
      isNot(contains("collection('riderWalletTransactions')")),
    );
    expect(statusSource, isNot(contains('runTransaction')));
  });

  test('legacy web tracking and chat use canonical callables', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();

    expect(source, contains("httpsCallable('updateDeliveryLiveLocation')"));
    expect(source, contains("httpsCallable('sendCircumMessage')"));
    expect(source,
        isNot(contains("collection('riderEarnings').doc(user.uid).set")));

    final riderChatStart = source.indexOf('Future<void> _sendRiderChatMessage');
    final riderChatEnd =
        source.indexOf('String _formatMessageTime', riderChatStart);
    expect(riderChatStart, isNonNegative);
    expect(riderChatEnd, greaterThan(riderChatStart));
    final riderChatSource = source.substring(riderChatStart, riderChatEnd);
    expect(riderChatSource, contains("httpsCallable('sendCircumMessage')"));
    expect(riderChatSource, isNot(contains("collection('chats')")));

    final senderChatStart = source.indexOf('Future<void> _sendMessage()');
    final senderChatEnd = source.indexOf('void _reset()', senderChatStart);
    expect(senderChatStart, isNonNegative);
    expect(senderChatEnd, greaterThan(senderChatStart));
    final senderChatSource = source.substring(senderChatStart, senderChatEnd);
    expect(senderChatSource, contains("httpsCallable('sendCircumMessage')"));
    expect(senderChatSource, isNot(contains("collection('chats')")));
  });
}
