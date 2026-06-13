import 'package:circum/app/delivery/booking_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sender cancellation is allowed before meaningful delivery progress',
      () {
    for (final status in [
      'pending',
      'awaiting_rider',
      'rider_assigned',
      'accepted',
    ]) {
      expect(BookingCancellationPolicy.canSenderCancel(status), isTrue);
    }
  });

  test('sender cancellation is blocked after delivery starts', () {
    for (final status in [
      'rider_en_route',
      'arrived',
      'picked_up',
      'in_transit',
      'delivered',
      'completed',
      'disputed',
      'cancelled',
      'cancelled_by_sender',
    ]) {
      expect(BookingCancellationPolicy.canSenderCancel(status), isFalse);
    }
  });
}
