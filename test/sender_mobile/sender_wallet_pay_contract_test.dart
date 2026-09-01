import 'dart:io';

import 'package:circum/app/sender_mobile/sender_finance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device readiness disables unavailable wallets but preserves cards', () {
    const card = SenderPaymentMethod(
      id: 'pm_card',
      brand: 'visa',
      last4: '4242',
    );
    const profile = SenderPaymentProfile(
      methods: [card],
      preference: SenderCheckoutPreference.askEveryCheckout,
    );

    final unavailable = profile.withPlatformPaySupport(
      applePay: false,
      googlePay: false,
    );
    final options = senderOrderedPaymentOptions(
      unavailable,
      platform: TargetPlatform.android,
    );

    expect(
      options.where(
        (item) => item.type == SenderPaymentProfileOptionType.googlePay,
      ),
      isEmpty,
    );
    expect(
      options.where(
        (item) => item.type == SenderPaymentProfileOptionType.savedCard,
      ),
      hasLength(1),
    );
    expect(options.last.type, SenderPaymentProfileOptionType.addPaymentMethod);
  });

  test(
    'wallet confirmation stays on backend-authoritative processing state',
    () {
      final source = File(
        'lib/app/sender_mobile/sender_booking_canvas.dart',
      ).readAsStringSync();
      final confirmation = source.substring(
        source.indexOf('Future<void> _confirmStripePayment'),
        source.indexOf('void _createPaidDelivery'),
      );

      expect(source, contains('isPlatformPaySupported'));
      expect(confirmation, contains('testEnv: false'));
      expect(
        confirmation,
        contains('paymentStatus: SenderPaymentStatus.processing'),
      );
      expect(
        confirmation,
        isNot(contains('paymentStatus: SenderPaymentStatus.paid')),
      );
      expect(confirmation, contains('FailureCode.Canceled'));
    },
  );

  test('iOS release entitlement declares the canonical merchant', () {
    final entitlements = File(
      'ios/Runner/RunnerRelease.entitlements',
    ).readAsStringSync();
    final startup = File('lib/main.dart').readAsStringSync();

    expect(entitlements, contains('com.apple.developer.in-app-payments'));
    expect(entitlements, contains('merchant.com.circum.app'));
    expect(
      startup,
      contains("Stripe.merchantIdentifier = 'merchant.com.circum.app'"),
    );
  });
}
