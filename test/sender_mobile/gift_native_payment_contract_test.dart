import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File('lib/app/sender_mobile/gift_payment_view.dart').readAsStringSync();

  test('Gift native payment preserves card and wallet method identity', () {
    expect(source, contains("'Apple Pay' => 'apple_pay'"));
    expect(source, contains("'Google Pay' => 'google_pay'"));
    expect(source, contains("'Saved card' => 'saved_card'"));
    expect(source, contains("'paymentMethod': _verifiedPaymentMethod"));
    expect(source, isNot(contains("'paymentMethod': 'card'")));
  });

  test('Gift Apple Pay and Google Pay use official platform confirmation', () {
    expect(source, contains("'giftApplePayButton'"));
    expect(source, contains("'giftGooglePayButton'"));
    expect(source, contains('confirmPlatformPayPaymentIntent'));
    expect(source, contains('PlatformPayConfirmParams.applePay'));
    expect(source, contains('PlatformPayConfirmParams.googlePay'));
  });

  test('Gift payment calls are bounded and reconcile with backend', () {
    expect(source, contains(".httpsCallable('finalizeGiftPayment')"));
    expect(source, contains('.timeout(_backendTimeout)'));
    expect(source, contains('.timeout(_paymentSheetPresentTimeout)'));
    expect(source,
        contains("'checkoutMode': kIsWeb ? 'web_checkout' : 'payment_intent'"));
  });

  test('Gift draft is submitted to backend without client authority write', () {
    expect(source, contains("'giftDraft': payload"));
    expect(source, contains('late final String _giftDraftId'));
    expect(source, contains("'giftDraftId': _giftDraftId"));
    expect(source, isNot(contains('await draftRef.set(')));
  });
}
