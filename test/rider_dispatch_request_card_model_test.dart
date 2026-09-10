import 'package:circum/app/send_package/models/dispatch_request.m..dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Rider card model preserves Business and Health+ offer authority', () {
    final request = DispatchRequest.fromJson({
      'pickupDetails': {
        'position': {
          'geohash': 'gcpvj',
          'geopoint': const GeoPoint(51.5, -0.1)
        },
      },
      'dropoffDetails': {
        'position': {
          'geohash': 'gcpvn',
          'geopoint': const GeoPoint(51.51, -0.11)
        },
      },
      'requestId': 'health_1',
      'code': '1234',
      'price': 20,
      'currency': 'GBP',
      'riderPayout': 13,
      'riderEarning': 13,
      'driverPayout': 13,
      'distanceText': '4.2 mi',
      'durationText': '18 min',
      'scheduledPickupWindow': '10:00–11:00',
      'serviceType': 'HEALTH_PLUS',
      'isHealthPlus': true,
      'isVanguard': true,
      'trustPoints': 6,
    });
    expect(request.riderPayout, 13);
    expect(request.distanceText, '4.2 mi');
    expect(request.pickupWindow, '10:00–11:00');
    expect(request.serviceType, 'HEALTH_PLUS');
    expect(request.isHealthPlus, isTrue);
    expect(request.requiresVanguard, isTrue);
    expect(request.trustPoints, 6);
  });
}
