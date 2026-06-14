import 'package:flutter_test/flutter_test.dart';
import 'package:circum/app/gifts/gift_request_policy.dart';

void main() {
  test('only the approved account can access Gifts private preview', () {
    expect(
      GiftRequestPolicy.canAccessPrivatePreview('ayojason600@gmail.com'),
      isTrue,
    );
    expect(
      GiftRequestPolicy.canAccessPrivatePreview('someone@example.com'),
      isFalse,
    );
  });

  test('gift request enforces the minimum budget', () {
    expect(
      GiftRequestPolicy.validate(
        senderEmail: 'sender@example.com',
        recipientName: 'Ayo',
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
    expect(GiftRequestPolicy.estimatedNetGiftBudget(100), 70);
  });

  test('sender statuses hide internal fulfilment detail', () {
    expect(GiftRequestPolicy.senderStatus('procuring'), 'Being prepared');
    expect(GiftRequestPolicy.senderStatus('packed'), 'Being prepared');
  });
}
