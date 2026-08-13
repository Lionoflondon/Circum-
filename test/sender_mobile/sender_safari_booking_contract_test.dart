import 'package:circum/app/sender_mobile/sender_booking_canvas.dart';
import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('Sender Safari booking address contract', () {
    test('typed text alone is not enough to continue', () {
      const draft = SenderBookingDraft(
        step: SenderBookingStep.pickup,
        pickupAddress: '29 St Fillans Road SE6 1DQ',
      );

      expect(isSenderTypedAddressSpecific(draft.pickupAddress), isTrue);
      expect(draft.canContinue, isFalse);
    });

    test('resolved UK coordinates are enough even when formatting differs', () {
      const pickup = SenderBookingDraft(
        step: SenderBookingStep.pickup,
        pickupAddress: '29 St Fillans Road, London SE6 1DQ, UK',
        pickupLat: 51.4329,
        pickupLng: -0.0205,
      );
      const dropoff = SenderBookingDraft(
        step: SenderBookingStep.dropoff,
        dropoffAddress: 'CR0 1GD, Greater London, England',
        dropoffLat: 51.3737,
        dropoffLng: -0.1004,
      );

      expect(pickup.canContinue, isTrue);
      expect(dropoff.canContinue, isTrue);
    });

    test('zero, NaN, infinite, and outside-UK coordinates are blocked', () {
      expect(isSenderValidUkCoordinate(0, 0), isFalse);
      expect(isSenderValidUkCoordinate(double.nan, -0.1), isFalse);
      expect(isSenderValidUkCoordinate(51.4, double.infinity), isFalse);
      expect(isSenderValidUkCoordinate(40.7, -73.9), isFalse);
    });
  });

  group('Sender booking map route authority', () {
    test('accepts current Croydon route polyline', () {
      const pickup = LatLng(51.4329, -0.0205);
      const dropoff = LatLng(51.3737, -0.1004);
      const points = [
        LatLng(51.4329, -0.0205),
        LatLng(51.4050, -0.0600),
        LatLng(51.3737, -0.1004),
      ];

      expect(senderBookingPolylineMatchesRoute(points, pickup, dropoff), isTrue);
    });

    test('rejects stale north London polyline for Croydon booking', () {
      const pickup = LatLng(51.4329, -0.0205);
      const dropoff = LatLng(51.3737, -0.1004);
      const staleNorthLondon = [
        LatLng(51.6850, -0.0350),
        LatLng(51.6500, -0.0800),
        LatLng(51.6170, -0.0300),
      ];

      expect(
        senderBookingPolylineMatchesRoute(staleNorthLondon, pickup, dropoff),
        isFalse,
      );
    });
  });
}
