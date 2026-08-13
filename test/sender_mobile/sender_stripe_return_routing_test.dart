import 'package:circum/app/sender_mobile/sender_stripe_return_routing.dart';
import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:circum/app/health_plus/health_plus_return_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gifts Stripe returns resolve inside the Sender app', () {
    for (final result in ['success', 'cancelled']) {
      final uri = Uri.parse(
        'https://circum-app-2797c.web.app/?app=gifts&gift_payment=$result&giftDraftId=draft_1&session_id=cs_test_1',
      );
      expect(
          resolveSenderInitialRouteName(uri), senderGiftPaymentReturnRouteName);
      expect(senderStripeReturnParameters(uri)['gift_payment'], result);
    }
  });

  test('legacy Gifts hash returns remain routable during rollout', () {
    final cancel = Uri.parse(
      'https://circum-app-2797c.web.app/#/sender-mobile/gifts/payment?giftDraftId=draft_1&payment=cancelled',
    );
    final success = Uri.parse(
      'https://circum-app-2797c.web.app/#/sender-mobile/gifts/confirmation?giftDraftId=draft_1&payment=success&session_id=cs_test_1',
    );
    expect(resolveSenderInitialRouteName(cancel),
        senderGiftPaymentReturnRouteName);
    expect(senderStripeReturnParameters(cancel)['gift_payment'], 'cancelled');
    expect(resolveSenderInitialRouteName(success),
        senderGiftPaymentReturnRouteName);
    expect(senderStripeReturnParameters(success)['gift_payment'], 'success');
  });

  test('Health, Business and Wallet returns resolve to app-owned surfaces', () {
    expect(
      resolveSenderInitialRouteName(Uri.parse(
        'https://circum-app-2797c.web.app/?app=health&health=cancelled',
      )),
      senderHealthReturnRouteName,
    );
    expect(
      resolveSenderInitialRouteName(Uri.parse(
        'https://circum-app-2797c.web.app/?app=business&section=invoicing&paymentStatus=payment-cancelled',
      )),
      senderBusinessReturnRouteName,
    );
    for (final result in ['success', 'cancelled']) {
      expect(
        resolveSenderInitialRouteName(Uri.parse(
          'https://circum-app-2797c.web.app/?app=sender&section=wallet&wallet_topup=$result',
        )),
        senderWalletReturnRouteName,
      );
    }
  });

  test('cancelled Sender checkout preserves its restored booking details', () {
    const restored = SenderBookingDraft(
      step: SenderBookingStep.findingRider,
      pickupAddress: '1 Pickup Street',
      dropoffAddress: '2 Dropoff Street',
      paymentStatus: SenderPaymentStatus.processing,
      bookingConfirmed: true,
      cardConfirmationStarted: true,
    );

    final cancelled = senderCancelledCheckoutDraft(restored);

    expect(cancelled.pickupAddress, restored.pickupAddress);
    expect(cancelled.dropoffAddress, restored.dropoffAddress);
    expect(cancelled.step, SenderBookingStep.payment);
    expect(cancelled.paymentStatus, SenderPaymentStatus.failed);
    expect(cancelled.bookingConfirmed, isFalse);
    expect(cancelled.cardConfirmationStarted, isFalse);
  });

  test('Wallet and Health+ returns explain outcomes without new effects', () {
    expect(
      senderWalletStripeReturnMessage(Uri.parse(
        'https://circum-app-2797c.web.app/?app=sender&section=wallet&wallet_topup=cancelled',
      )),
      contains('No new charge was made'),
    );
    expect(
      healthPlusStripeReturnMessage(
        returnState: 'success',
        paymentStatus: 'paid',
      ),
      contains('payment confirmed'),
    );
    expect(
      healthPlusStripeReturnMessage(returnState: 'cancelled'),
      contains('no new charge was made'),
    );
  });
}
