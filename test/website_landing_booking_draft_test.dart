import 'dart:convert';
import 'package:circum/website/shared/landing_booking_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 8, 10);
  test(
      'handoff preserves trimmed address text but carries no verified price or coordinates',
      () {
    final raw =
        LandingBookingDraft('  London NW1  ', 'London SE1 ', now).encode();
    final draft = LandingBookingDraft.decode(raw, now)!;
    expect(draft.pickup, 'London NW1');
    expect(draft.destination, 'London SE1');
    expect((jsonDecode(raw) as Map).keys,
        unorderedEquals(['pickup', 'destination', 'createdAt']));
  });
  test('expired and future drafts cannot replace booking details', () {
    for (final time in [
      now.subtract(const Duration(minutes: 31)),
      now.add(const Duration(minutes: 2))
    ]) {
      expect(
          LandingBookingDraft.decode(
              LandingBookingDraft('NW1', 'SE1', time).encode(), now),
          isNull);
    }
  });
  test('malformed and oversized storage fails closed', () {
    for (final raw in [
      null,
      'not json',
      '[]',
      '{}',
      '{"pickup":3}',
      'x' * 4097,
      LandingBookingDraft('', 'SE1', now).encode(),
      LandingBookingDraft('NW1', 'x' * 301, now).encode()
    ]) {
      expect(LandingBookingDraft.decode(raw, now), isNull);
    }
  });
}
