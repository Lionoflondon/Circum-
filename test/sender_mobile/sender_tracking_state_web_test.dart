import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender mobile preserves distinct pickup and drop-off coordinates', () {
    final source = File('lib/app/send_package/bloc/send_package_bloc.dart')
        .readAsStringSync();

    expect(
      source,
      contains(
        'GeoPoint(\n'
        '          event.dropoffDetails.address.lat, '
        'event.dropoffDetails.address.lng)',
      ),
    );
    expect(
      source,
      isNot(
        contains(
          'GeoPoint(\n'
          '          event.dropoffDetails.address.lat, '
          'event.pickupDetails.address.lng)',
        ),
      ),
    );
  });

  test('Sender Web reads canonical delivery lifecycle fields', () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();

    expect(source, contains('String _backendStatusFromDelivery'));
    expect(source, contains("data['deliveryStage']"));
    expect(source, contains("data['deliveryStatus']"));
    expect(source, contains("data['trackingStatus']"));
    expect(source, contains("data['status']"));
  });

  test('Sender Web represents the backend tracking phases', () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    const labels = [
      'Finding a rider',
      'Rider assigned',
      'Travelling to pickup',
      'Arrived at pickup',
      'Pickup verified',
      'In transit',
      'Arrived at drop-off',
      'Delivered',
      'Closed',
      'Needs attention',
    ];

    for (final label in labels) {
      expect(source, contains(label));
    }
  });
}
