import 'package:flutter_test/flutter_test.dart';

import 'package:circum/app/sender_mobile/sender_booking_state.dart';

void main() {
  test('resolved Google address can continue without a numeric display label', () {
    const draft = SenderBookingDraft(
      pickupAddress: 'The Shard, London Bridge Street, London, United Kingdom',
      pickupLat: 51.5045,
      pickupLng: -0.0865,
    );

    expect(draft.canContinue, isTrue);
  });

  test('resolved Flat 190 Edridge Road address remains continuable', () {
    const draft = SenderBookingDraft(
      pickupAddress: 'Flat 190, 4 Edridge Road, Croydon CR0 1GD',
      pickupLat: 51.3721,
      pickupLng: -0.1004,
    );

    expect(draft.canContinue, isTrue);
  });

  test('unresolved prediction cannot continue', () {
    const draft = SenderBookingDraft(
      pickupAddress: 'The Shard, London Bridge Street, London, United Kingdom',
    );

    expect(draft.canContinue, isFalse);
  });

  test('manual specific address remains eligible for canonical resolution', () {
    const draft = SenderBookingDraft(
      pickupAddress: '32 London Bridge Street, London SE1 9SG',
    );

    expect(draft.canContinue, isTrue);
  });

  test('invalid coordinates do not make an address continuable', () {
    const draft = SenderBookingDraft(
      pickupAddress: 'The Shard, London Bridge Street, London, United Kingdom',
      pickupLat: double.nan,
      pickupLng: -0.0865,
    );

    expect(draft.canContinue, isFalse);
  });
}
