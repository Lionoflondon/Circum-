import 'package:flutter_test/flutter_test.dart';
import 'package:circum/app/gifts/gift_request_policy.dart';

void main() {
  test('gift request enforces the minimum budget', () {
    expect(
      GiftRequestPolicy.validate(
        senderEmail: 'sender@example.com',
        recipientName: 'Ayo',
        recipientPhone: '07123456789',
        recipientEmail: 'recipient@example.com',
        relationship: 'Friend',
        occasion: 'Birthday',
        deliveryAddress: 'London',
        deliveryDate: DateTime(2026, 7, 1),
        grossBudget: 49,
      ),
      'Gift budgets start from £50.',
    );
  });

  test('net gift budget reserves operational costs', () {
    expect(GiftRequestPolicy.estimatedStripeFee(100), 1.7);
    expect(GiftRequestPolicy.estimatedNetGiftBudget(100), 98.3);
  });

  test('recipient phone and valid email are required before payment', () {
    final common = DateTime(2026, 7, 1);
    expect(
        GiftRequestPolicy.validate(
            senderEmail: 'sender@example.com',
            recipientName: 'Ayo',
            recipientEmail: 'recipient@example.com',
            relationship: 'Friend',
            occasion: 'Birthday',
            deliveryAddress: 'London',
            deliveryDate: common,
            grossBudget: 100),
        'Enter the recipient phone number.');
    expect(
        GiftRequestPolicy.validate(
            senderEmail: 'sender@example.com',
            recipientName: 'Ayo',
            recipientPhone: '07123456789',
            recipientEmail: 'invalid',
            relationship: 'Friend',
            occasion: 'Birthday',
            deliveryAddress: 'London',
            deliveryDate: common,
            grossBudget: 100),
        'Enter a valid recipient email address.');
  });

  test('unpaid gifts remain payment pending', () {
    expect(GiftRequestPolicy.senderStatus('draft'), 'Payment pending');
    expect(
        GiftRequestPolicy.senderStatus('payment_pending'), 'Payment pending');
    expect(GiftRequestPolicy.senderStatus('submitted_for_review'),
        'Request submitted');
  });

  test('sender statuses hide internal fulfilment detail', () {
    expect(GiftRequestPolicy.senderStatus('procuring'), 'Being prepared');
    expect(GiftRequestPolicy.senderStatus('packed'), 'Being prepared');
  });
}
