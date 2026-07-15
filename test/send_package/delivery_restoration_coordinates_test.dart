import 'package:circum/app/send_package/models/delivery_restoration_coordinates.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restores pickup and drop-off from their independent coordinates', () {
    final restored = restoreDeliveryCoordinates({
      'pickupDetails': {
        'position': {'geopoint': const GeoPoint(51.5033, -0.1195)},
      },
      'dropoffDetails': {
        'position': {'geopoint': const GeoPoint(51.5155, -0.0922)},
      },
    });

    expect(restored.pickup.lat, 51.5033);
    expect(restored.pickup.lng, -0.1195);
    expect(restored.dropoff.lat, 51.5155);
    expect(restored.dropoff.lng, -0.0922);
    expect(restored.dropoff.lat, isNot(restored.pickup.lat));
    expect(restored.dropoff.lng, isNot(restored.pickup.lng));
  });

  test('supports restored coordinate maps used by cached snapshots', () {
    final restored = restoreDeliveryCoordinates({
      'pickupDetails': {
        'position': {
          'geopoint': {'latitude': 51.5033, 'longitude': -0.1195},
        },
      },
      'dropoffDetails': {
        'position': {
          'geopoint': {'lat': 51.5155, 'lng': -0.0922},
        },
      },
    });

    expect(restored.pickup.lat, 51.5033);
    expect(restored.dropoff.lat, 51.5155);
  });

  test('rejects a delivery without independent drop-off coordinates', () {
    expect(
      () => restoreDeliveryCoordinates({
        'pickupDetails': {
          'position': {'geopoint': const GeoPoint(51.5033, -0.1195)},
        },
        'dropoffDetails': const <String, dynamic>{},
      }),
      throwsStateError,
    );
  });
}
