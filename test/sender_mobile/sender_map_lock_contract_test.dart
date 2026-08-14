import 'dart:io';

import 'package:circum/app/sender_mobile/sender_booking_canvas.dart';
import 'package:circum/app/sender_mobile/sender_tracking_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  const pickup = LatLng(51.5259, -0.0877);
  const dropoff = LatLng(51.5074, -0.1278);
  const rider = LatLng(51.5142, -0.1020);

  test('booking map camera identity ignores adaptive sheet presentation', () {
    final expandedSheet = senderBookingMapCameraIdentityForTest(
      pickup: pickup,
      dropoff: dropoff,
      showDestination: true,
      routePointCount: 12,
      markerCount: 2,
    );
    final collapsedSheet = senderBookingMapCameraIdentityForTest(
      pickup: pickup,
      dropoff: dropoff,
      showDestination: true,
      routePointCount: 12,
      markerCount: 2,
    );

    expect(collapsedSheet, expandedSheet);
  });

  test('booking map camera identity changes for real route inputs', () {
    final original = senderBookingMapCameraIdentityForTest(
      pickup: pickup,
      dropoff: dropoff,
      showDestination: true,
      routePointCount: 12,
      markerCount: 2,
    );
    final changedDropoff = senderBookingMapCameraIdentityForTest(
      pickup: pickup,
      dropoff: const LatLng(51.5010, -0.1416),
      showDestination: true,
      routePointCount: 12,
      markerCount: 2,
    );

    expect(changedDropoff, isNot(original));
  });

  test('tracking map camera identity ignores panel extent changes', () {
    final compactPanel = senderTrackingMapCameraIdentityForTest(
      pickup: pickup,
      dropoff: dropoff,
      rider: rider,
      delivered: false,
      showRoute: true,
      progress: 42,
      routePointCount: 18,
      riderRouteIndex: 4,
    );
    final expandedPanel = senderTrackingMapCameraIdentityForTest(
      pickup: pickup,
      dropoff: dropoff,
      rider: rider,
      delivered: false,
      showRoute: true,
      progress: 42,
      routePointCount: 18,
      riderRouteIndex: 4,
    );

    expect(expandedPanel, compactPanel);
  });

  test('tracking map camera identity changes for canonical movement', () {
    final original = senderTrackingMapCameraIdentityForTest(
      pickup: pickup,
      dropoff: dropoff,
      rider: rider,
      delivered: false,
      showRoute: true,
      progress: 42,
      routePointCount: 18,
      riderRouteIndex: 4,
    );
    final movedRider = senderTrackingMapCameraIdentityForTest(
      pickup: pickup,
      dropoff: dropoff,
      rider: const LatLng(51.5160, -0.1001),
      delivered: false,
      showRoute: true,
      progress: 42,
      routePointCount: 18,
      riderRouteIndex: 4,
    );

    expect(movedRider, isNot(original));
  });

  test('map camera movement is not wired to sheet extent controllers', () {
    final booking = File('lib/app/sender_mobile/sender_booking_canvas.dart')
        .readAsStringSync();
    final tracking = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();

    expect(booking, contains('_lastCameraRouteKey'));
    expect(booking, contains('senderBookingMapCameraIdentityForTest'));
    expect(booking, isNot(contains('_bookingSheetController.addListener')));

    expect(tracking, contains('_lastCameraSnapshotKey'));
    expect(tracking, contains('senderTrackingMapCameraIdentityForTest'));
    expect(tracking, isNot(contains('_sheetController.addListener')));
  });
}
