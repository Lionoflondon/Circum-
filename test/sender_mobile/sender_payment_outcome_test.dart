import 'package:circum/app/sender_mobile/sender_payment_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final status in [
    'checkout_created',
    'payment_processing',
    'requires_action',
    'failed',
    'cancelled',
    '',
  ]) {
    test('$status cannot confirm a reserved booking', () {
      expect(confirmedSenderPaymentRequestId({
        'paymentStatus': status,
        'requestId': 'reserved_booking',
      }), isEmpty);
    });
  }

  test('explicit paid outcome can confirm a booking', () {
    for (final status in ['paid', 'succeeded']) {
      expect(confirmedSenderPaymentRequestId({
        'paymentStatus': status,
        'requestId': 'confirmed_booking',
      }), 'confirmed_booking');
    }
  });

  test('payment status takes precedence over a conflicting generic status', () {
    expect(confirmedSenderPaymentRequestId({
      'paymentStatus': 'checkout_created',
      'status': 'succeeded',
      'requestId': 'reserved_booking',
    }), isEmpty);
  });

  test('success without a booking ID does not confirm delivery', () {
    expect(confirmedSenderPaymentRequestId({'status': 'succeeded'}), isEmpty);
  });
}
