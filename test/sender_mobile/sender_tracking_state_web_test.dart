import 'dart:io';

import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/app/send_package/models/delivery_restoration_coordinates.dart';
import 'package:circum/app/send_package/models/place_coordinates.m.dart';
import 'package:circum/app/sender_mobile/sender_tracking_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('Sender mobile preserves distinct pickup and drop-off coordinates', () {
    final restored = restoreDeliveryCoordinates({
      'pickupDetails': {
        'position': {
          'geopoint': {'latitude': 51.5, 'longitude': -0.1},
        },
      },
      'dropoffDetails': {
        'position': {
          'geopoint': {'latitude': 51.7, 'longitude': -0.3},
        },
      },
    });

    expect(restored.pickup.lat, 51.5);
    expect(restored.pickup.lng, -0.1);
    expect(restored.dropoff.lat, 51.7);
    expect(restored.dropoff.lng, -0.3);
  });

  test('Sender Web reads canonical delivery lifecycle fields', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();

    expect(source, contains('String _backendStatusFromDelivery'));
    expect(source, contains("data['deliveryStage']"));
    expect(source, contains("data['deliveryStatus']"));
    expect(source, contains("data['trackingStatus']"));
    expect(source, contains("data['status']"));
  });

  test('Sender Web represents the backend tracking phases', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
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

  test('Sender mobile normalizes backend tracking fields', () {
    expect(
      senderTrackingStateForBackendStatus(' navigating-to-pickup '),
      SenderTrackingState.riderEnRouteToPickup,
    );
    expect(
      senderTrackingStateForBackendStatus('ARRIVED AT PICKUP'),
      SenderTrackingState.riderArrivedAtPickup,
    );
    expect(
      senderTrackingStateForBackendStatus('pickup_verified'),
      SenderTrackingState.pickupComplete,
    );
    expect(
      senderTrackingStateForBackendStatus('outForDelivery'),
      SenderTrackingState.inTransit,
    );
    expect(
      senderTrackingStateForBackendStatus('pin-required'),
      SenderTrackingState.riderArrivingAtDropoff,
    );
    expect(
      senderTrackingStateForBackendStatus('sender_no_show_pickup'),
      SenderTrackingState.cancelled,
    );
    expect(
      senderTrackingStateForBackendStatus('issue_reported'),
      SenderTrackingState.issue,
    );
    expect(
      senderTrackingStateForBackendStatus('awaiting_adjustment_review'),
      SenderTrackingState.adjustmentUnderReview,
    );
    expect(
      senderTrackingStateForBackendStatus('more_evidence_requested'),
      SenderTrackingState.adjustmentMoreEvidence,
    );
    expect(
      senderTrackingStateForBackendStatus('awaiting_sender_payment'),
      SenderTrackingState.adjustmentApproved,
    );
    expect(
      senderTrackingStateForBackendStatus('rejected_by_admin'),
      SenderTrackingState.adjustmentRejected,
    );
    expect(
      senderTrackingStateForBackendStatus('unknown_future_status'),
      isNull,
    );
  });

  test('Sender mobile gates live lifecycle on backend proof fields', () {
    expect(
      senderTrackingStateForBackendData({
        'status': 'in_transit',
      }),
      SenderTrackingState.findingRider,
    );
    expect(
      senderTrackingStateForBackendData({
        'status': 'in_transit',
        'riderId': 'rider_123',
      }),
      SenderTrackingState.riderArrivedAtPickup,
    );
    expect(
      senderTrackingStateForBackendData({
        'status': 'in_transit',
        'riderId': 'rider_123',
        'collectedAt': DateTime(2026, 7, 30),
      }),
      SenderTrackingState.inTransit,
    );
    expect(
      senderTrackingStateForBackendData({
        'status': 'collected',
        'riderId': 'rider_123',
      }),
      SenderTrackingState.riderArrivedAtPickup,
    );
    expect(
      senderTrackingStateForBackendData({
        'status': 'collected',
        'riderId': 'rider_123',
        'collectionPinVerified': true,
      }),
      SenderTrackingState.pickupComplete,
    );
  });

  test('Sender mobile contains user-facing copy for every tracking stage', () {
    for (final stage in SenderTrackingState.values) {
      final copy = senderTrackingContentFor(stage);
      expect(copy.title.trim(), isNotEmpty);
      expect(copy.body.trim(), isNotEmpty);
    }

    expect(
      senderTrackingContentFor(SenderTrackingState.riderArrivingAtDropoff)
          .title,
      'Your Circum Rider is almost there',
    );
    expect(
      senderTrackingContentFor(SenderTrackingState.adjustmentUnderReview).body,
      contains('Delivery and payment are paused'),
    );
    expect(
      senderTrackingContentFor(SenderTrackingState.adjustmentApproved).body,
      contains('additional payment'),
    );
  });

  test('Sender Web exposes every delivery adjustment review state', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();

    for (final marker in [
      'awaiting_admin_review',
      'more_evidence_requested',
      'awaiting_sender_payment',
      'rejected_by_admin',
      'Adjustment under review',
      'More evidence requested',
      'Adjustment approved',
      'Adjustment rejected',
    ]) {
      expect(source, contains(marker));
    }
  });

  test('Sender mobile exposes receiver PIN only in active delivery stages', () {
    expect(
      senderTrackingContentFor(SenderTrackingState.riderAssigned)
          .showReceiverPin,
      isFalse,
    );
    expect(
      senderTrackingContentFor(SenderTrackingState.pickupComplete)
          .showReceiverPin,
      isTrue,
    );
    expect(
      senderTrackingContentFor(SenderTrackingState.delivered).showReceiverPin,
      isFalse,
    );
  });

  test('Sender mobile active panel renders stage-specific tracking content',
      () {
    final source = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();

    expect(source, contains('senderTrackingContentFor'));
    expect(source, contains('SenderTrackingState.findingRider'));
    expect(source, contains('SenderTrackingState.riderArrivingAtDropoff'));
    expect(source, contains('PINCard'));
  });

  test('Sender tracking map adapter creates live Google map snapshot', () {
    final content = senderTrackingContentFor(SenderTrackingState.inTransit);
    final snapshot = SenderTrackingMapAdapter.snapshotFor(
      SendPackageState(
        pickupCoordinate: PlaceCoordinate(lat: 51.501, lng: -0.141),
        desinationCoordinate: PlaceCoordinate(lat: 51.515, lng: -0.092),
        riderLocation: PlaceCoordinate(lat: 51.507, lng: -0.118),
        polylineCoordinates: const [
          LatLng(51.501, -0.141),
          LatLng(51.507, -0.118),
          LatLng(51.515, -0.092),
        ],
      ),
      content: content,
      stateDelivered: false,
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.pickup.latitude, 51.501);
    expect(snapshot.dropoff.longitude, -0.092);
    expect(snapshot.rider?.latitude, 51.507);
    expect(snapshot.completedRoute, hasLength(3));
    expect(snapshot.remainingRoute.first, snapshot.rider);
  });

  test(
      'Sender tracking map adapter falls back when coordinates are unavailable',
      () {
    final snapshot = SenderTrackingMapAdapter.snapshotFor(
      SendPackageState(),
      content: senderTrackingContentFor(SenderTrackingState.findingRider),
      stateDelivered: false,
    );

    expect(snapshot, isNull);
  });
}
