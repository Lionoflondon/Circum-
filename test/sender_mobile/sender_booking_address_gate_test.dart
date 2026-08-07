import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical landmark pickup enables confirmation without postcode text',
      () {
    const draft = SenderBookingDraft(
      pickupAddress: 'The Shard, London Bridge Street, London, United Kingdom',
      pickupLat: 51.5045,
      pickupLng: -0.0865,
    );

    expect(draft.canContinue, isTrue);
  });

  test('prediction text without canonical coordinates cannot confirm pickup',
      () {
    const draft = SenderBookingDraft(
      pickupAddress: 'The Shard, London Bridge Street, London, United Kingdom',
    );

    expect(draft.canContinue, isFalse);
  });

  test('canonical drop-off coordinates enable confirmation', () {
    const draft = SenderBookingDraft(
      step: SenderBookingStep.dropoff,
      dropoffAddress: 'Battersea Power Station, London, United Kingdom',
      dropoffLat: 51.4817,
      dropoffLng: -0.1441,
    );

    expect(draft.canContinue, isTrue);
  });

  test('invalid and non-UK coordinates remain rejected', () {
    expect(isSenderCanonicalCoordinateUsable(0, 0), isFalse);
    expect(isSenderCanonicalCoordinateUsable(double.nan, -0.1), isFalse);
    expect(isSenderCanonicalCoordinateUsable(40.7, -74), isFalse);
    expect(isSenderCanonicalCoordinateUsable(51.5045, -0.0865), isTrue);
  });
}
