import 'package:circum/app/delivery/booking_cancellation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sender cancellation is allowed before meaningful delivery progress',
      () {
    for (final status in [
      'pending',
      'awaiting_rider',
      'finding_rider',
      'broadcast',
      'rider_assigned',
      'accepted',
      'navigating_to_pickup',
      'en_route_to_pickup',
      'rider_en_route',
      'arrived',
      'arrived_at_pickup',
      'waiting',
      'waiting_for_collection',
      'waiting_charge_active',
      'no_show_review',
      'pickup_verification',
    ]) {
      expect(BookingCancellationPolicy.canSenderCancel(status), isTrue);
    }
  });

  test('sender cancellation is blocked after delivery starts', () {
    for (final status in [
      'pickup_verified',
      'picked_up',
      'collected',
      'in_transit',
      'navigating_to_dropoff',
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
