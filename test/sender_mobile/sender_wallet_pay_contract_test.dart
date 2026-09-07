import 'dart:io';

import 'package:circum/app/sender_mobile/sender_finance.dart';
import 'package:circum/env/env.dart';
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
      expect(confirmation, contains('testEnv: Env.googlePayTestEnvironment'));
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

  test('wallet management is production-safe and bounded', () {
    final source = File(
      'lib/app/sender_mobile/sender_wallet.dart',
    ).readAsStringSync();

    expect(source, contains('isPlatformPaySupported()'));
    expect(source, contains('testEnv: Env.googlePayTestEnvironment'));
    expect(source, contains('_senderWalletActionTimeout'));
    expect(source, contains('.timeout(_senderWalletActionTimeout)'));
    expect(source, isNot(contains('error.error.localizedMessage')));
    expect(source, contains('finally {'));
    expect(source, contains('setState(() => _loading = false)'));
  });

  test('Apple and Google merchant paths use coherent configuration', () {
    final startup = File('lib/main.dart').readAsStringSync();
    final entitlements = File(
      'ios/Runner/RunnerRelease.entitlements',
    ).readAsStringSync();
    final wallet = File(
      'lib/app/sender_mobile/sender_wallet.dart',
    ).readAsStringSync();
    final checkout = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();

    expect(
      startup,
      contains("Stripe.merchantIdentifier = 'merchant.com.circum.app'"),
    );
    expect(entitlements, contains('merchant.com.circum.app'));
    expect(
      wallet,
      contains(
          "const _senderWalletMerchantDisplayName = 'Circum Technologies'"),
    );
    expect(wallet, contains('label: _senderWalletMerchantDisplayName'));
    expect(wallet, contains('merchantName: _senderWalletMerchantDisplayName'));
    expect(
      RegExp(r'merchantDisplayName: _senderWalletMerchantDisplayName')
          .allMatches(wallet),
      hasLength(2),
    );
    expect(wallet, isNot(contains('Circum payment method')));
    expect(
      RegExp(r'testEnv: Env.googlePayTestEnvironment').allMatches(wallet),
      hasLength(3),
    );
    expect(wallet, contains('confirmPlatformPaySetupIntent('));
    expect(wallet, contains('PlatformPayConfirmParams.applePay('));
    expect(checkout, contains('testEnv: Env.googlePayTestEnvironment'));
  });

  test('wallet payment controls use branded non-empty action surfaces', () {
    final wallet = File(
      'lib/app/sender_mobile/sender_wallet.dart',
    ).readAsStringSync();

    expect(wallet, contains('class _WalletNotice'));
    expect(wallet, contains('SnackBarBehavior.floating'));
    expect(wallet, contains('AppGlassContainer'));
    expect(wallet, contains('class _PaymentMethodActionSheet'));
    expect(wallet, contains('class _PaymentMethodMenuButton'));
    expect(wallet, contains('Set as default'));
    expect(wallet, contains('Remove card'));
    expect(wallet, contains('class _RedeemRothCardDialog'));
    expect(wallet, contains('_confirmRemovePaymentMethod'));
    expect(wallet, isNot(contains('PopupMenuButton<String>')));
    expect(wallet, isNot(contains('Custom card names are not available yet')));
    expect(
      wallet,
      isNot(contains('setup was cancelled or could not be completed')),
    );
  });

  test('payment sheets present the legal company display name', () {
    final paymentSources = [
      File('lib/app/sender_mobile/sender_wallet.dart').readAsStringSync(),
      File('lib/app/sender_mobile/sender_booking_canvas.dart')
          .readAsStringSync(),
      File('lib/app/sender_mobile/gift_payment_view.dart').readAsStringSync(),
      File('lib/app/send_package/view/ratings.dart').readAsStringSync(),
      File('lib/app/account/bloc/account_bloc.dart').readAsStringSync(),
    ].join('\n');

    expect(paymentSources, contains('Circum Technologies'));
    expect(paymentSources, isNot(contains("merchantDisplayName: 'Circum'")));
    expect(paymentSources, isNot(contains("merchantName: 'Circum'")));
    expect(paymentSources, isNot(contains("label: 'Circum Gift'")));
  });

  test('Sender checkout submits Roth and selected payment rail together', () {
    final canvas = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();
    final paymentStart = canvas.substring(
      canvas.indexOf('void _setRoth('),
      canvas.indexOf('Future<void> _openStripeCheckout'),
    );

    expect(paymentStart, contains('SenderPaymentSplit.calculate('));
    expect(paymentStart, contains('rothEnabled: split.rothEnabled'));
    expect(
        paymentStart, contains('rothAppliedAmount: split.rothAppliedAmount'));
    expect(paymentStart, contains('remainingAmount: split.remainingAmount'));
    expect(paymentStart, contains('paymentSplitSummary: split.splitSummary'));
    expect(
      paymentStart,
      contains("fallbackMethod: split.fallbackMethod == null"),
    );
    expect(paymentStart, contains("? 'roth'"));
    expect(paymentStart, contains("? 'saved_card'"));
    expect(
      paymentStart,
      contains('_stripeFallbackMethodValue(split.fallbackMethod!)'),
    );
    expect(
      paymentStart,
      contains('paymentMethodId: draft.selectedPaymentMethodId'),
    );
    expect(paymentStart, contains('StartSenderPaymentSession('));
  });

  test('Google Pay mode follows the Stripe publishable key', () {
    expect(Env.googlePayTestEnvironmentForKey('pk_test_example'), isTrue);
    expect(Env.googlePayTestEnvironmentForKey('pk_live_example'), isFalse);
    expect(
      () => Env.googlePayTestEnvironmentForKey(''),
      throwsA(isA<FormatException>()),
    );
  });

  test('Android release declares the Google Wallet API', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android:name="com.google.android.gms.wallet.api.enabled"'),
    );
    expect(manifest, contains('android:value="true"'));
  });
}
