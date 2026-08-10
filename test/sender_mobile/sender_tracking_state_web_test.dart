import 'dart:io';

import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/app/send_package/models/delivery_restoration_coordinates.dart';
import 'package:circum/app/send_package/models/place_coordinates.m.dart';
import 'package:circum/app/sender_mobile/sender_booking_canvas.dart';
import 'package:circum/app/sender_mobile/circum_route_presentation.dart';
import 'package:circum/app/sender_mobile/sender_tracking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  test('pending no-show collection is not presented as a completed charge', () {
    final source = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();
    expect(source, contains("financial['customerCollected'] != 7"));
    expect(source, contains("settlementStatus != 'settled'"));
  });
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

  test('canonical terminal status cannot regress when proof is delayed', () {
    expect(
      senderTrackingStateForBackendData({
        'status': 'delivered',
        'riderId': 'rider_123',
        'waiting': {'active': true},
      }),
      SenderTrackingState.delivered,
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

  test('Sender booking map is not disabled on Web when coordinates exist', () {
    expect(
      senderBookingMapShouldUseGoogle(const LatLng(51.501, -0.141)),
      isTrue,
    );
    expect(senderBookingMapShouldUseGoogle(null), isFalse);
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

  test('Sender tracking map adapter reads backend position geopoints', () {
    final snapshot = SenderTrackingMapAdapter.snapshotFor(
      SendPackageState(
        activeDeliveryData: {
          'pickupDetails': {
            'position': {
              'geopoint': {'latitude': 51.501, 'longitude': -0.141},
            },
          },
          'dropoffDetails': {
            'position': {
              'geopoint': {'latitude': 51.515, 'longitude': -0.092},
            },
          },
        },
      ),
      content: senderTrackingContentFor(SenderTrackingState.findingRider),
      stateDelivered: false,
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.pickup.latitude, 51.501);
    expect(snapshot.dropoff.longitude, -0.092);
  });

  test('Sender tracking map adapter reads REST serialized geopoints', () {
    final snapshot = SenderTrackingMapAdapter.snapshotFor(
      SendPackageState(
        activeDeliveryData: {
          'pickupDetails': {
            'position': {
              'geopoint': {
                'geoPointValue': {
                  'latitude': 51.4432992,
                  'longitude': -0.0092803,
                },
              },
            },
          },
          'dropoffDetails': {
            'position': {
              'geopoint': {
                'geoPointValue': {
                  'latitude': 51.5034878,
                  'longitude': -0.1276965,
                },
              },
            },
          },
        },
      ),
      content: senderTrackingContentFor(SenderTrackingState.findingRider),
      stateDelivered: false,
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.pickup.latitude, 51.4432992);
    expect(snapshot.dropoff.longitude, -0.1276965);
  });

  test('Sender tracking map adapter reads canonical flat route coordinates',
      () {
    final snapshot = SenderTrackingMapAdapter.snapshotFor(
      SendPackageState(
        activeDeliveryData: {
          'pickupLat': 51.4432992,
          'pickupLng': -0.0092803,
          'dropoffLat': 51.5034878,
          'dropoffLng': -0.1276965,
        },
      ),
      content: senderTrackingContentFor(SenderTrackingState.findingRider),
      stateDelivered: false,
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.pickup.latitude, 51.4432992);
    expect(snapshot.dropoff.longitude, -0.1276965);
  });

  test('terminal map excludes live rider and never fabricates route geometry',
      () {
    final snapshot = SenderTrackingMapAdapter.snapshotFor(
      SendPackageState(
        pickupCoordinate: PlaceCoordinate(lat: 51.5045, lng: -0.0865),
        desinationCoordinate: PlaceCoordinate(lat: 51.4820203, lng: -0.1444907),
        riderLocation: PlaceCoordinate(lat: 59.0, lng: 1.0),
      ),
      content: senderTrackingContentFor(SenderTrackingState.delivered),
      stateDelivered: true,
    );

    expect(snapshot, isNotNull);
    expect(snapshot!.rider, isNull);
    expect(snapshot.route, isEmpty);
  });

  test('route geometry is present only when authoritative points exist', () {
    final absent = SenderTrackingMapAdapter.snapshotFor(
      SendPackageState(
        pickupCoordinate: PlaceCoordinate(lat: 51.5045, lng: -0.0865),
        desinationCoordinate:
            PlaceCoordinate(lat: 51.4820203, lng: -0.1444907),
      ),
      content: senderTrackingContentFor(SenderTrackingState.delivered),
      stateDelivered: true,
    );
    final present = SenderTrackingMapAdapter.snapshotFor(
      SendPackageState(
        pickupCoordinate: PlaceCoordinate(lat: 51.5045, lng: -0.0865),
        desinationCoordinate:
            PlaceCoordinate(lat: 51.4820203, lng: -0.1444907),
        polylineCoordinates: const [
          LatLng(51.5045, -0.0865),
          LatLng(51.495, -0.12),
          LatLng(51.4820203, -0.1444907),
        ],
      ),
      content: senderTrackingContentFor(SenderTrackingState.delivered),
      stateDelivered: true,
    );

    expect(absent?.route, isEmpty);
    expect(present?.route, hasLength(3));
    expect(present?.completedRoute, hasLength(3));
    expect(present?.remainingRoute, isEmpty);
  });

  test('CIRCUM energy pulse stays on canonical route points', () {
    final route = List<int>.generate(24, (index) => index);
    final segment = CircumRoutePresentation.energySegment(route, 0.6);

    expect(segment, everyElement(isIn(route)));
    expect(segment.length, inInclusiveRange(2, 12));
    expect(CircumRoutePresentation.base, isNot(const Color(0xFFF44336)));
  });

  test('tracking renderer uses CIRCUM route contract and reduced motion', () {
    final source = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();
    expect(source, contains("PolylineId('circum_route_energy')"));
    expect(source, contains('maybeDisableAnimationsOf'));
    expect(source, isNot(contains("PolylineId('remaining_route')")));
  });

  test('assigned Rider trust view projects photo, rank, vehicle and experience', () {
    final rider = AssignedRiderTrustView.fromDelivery({
      'assignedRiderId': 'rider-1',
      'assignedRiderProfile': {
        'riderId': 'rider-1',
        'displayName': 'Ayo Rider',
        'username': 'ayo',
        'photoUrl': 'https://images.example/rider.jpg',
        'photoVersion': 3,
        'rank': 'veteran',
        'rankAssigned': true,
        'verified': true,
        'completedDeliveries': 42,
        'rating': 4.8,
        'vehicle': {
          'type': 'Car',
          'manufacturer': 'Volvo',
          'model': 'EX30',
          'colour': 'Blue',
          'registration': 'AB12 CDE',
        },
        'qualifications': ['Vanguard'],
      },
      'riderEtaText': '6 min',
      'riderDistanceText': '1.2 mi',
    });

    expect(rider.displayName, 'Ayo Rider');
    expect(rider.photoUrl, 'https://images.example/rider.jpg');
    expect(rider.rank, 'Veteran');
    expect(rider.rankAssigned, isTrue);
    expect(rider.vehicleLabel, 'Blue · Volvo EX30 · Car · AB12 CDE');
    expect(rider.experienceLabel, '42 completed · 4.8 rating');
    expect(rider.etaDistanceLabel, '6 min · 1.2 mi');
    expect(rider.qualifications, ['Vanguard']);
  });

  test('assigned Rider trust view fails safely for missing or invalid fields', () {
    final rider = AssignedRiderTrustView.fromDelivery({
      'assignedRiderId': 'rider-2',
      'riderName': 'Circum Rider',
      'riderPhotoUrl': 'http://insecure.example/rider.jpg',
      'riderRating': 9,
    });

    expect(rider.photoUrl, isEmpty);
    expect(rider.rank, 'Agent');
    expect(rider.rating, isNull);
    expect(rider.vehicleLabel, 'Vehicle details updating');
    expect(rider.etaDistanceLabel, 'Updating ETA');
  });

  testWidgets('Rider card drops old identity on reassignment and closes contact terminally',
      (tester) async {
    SendPackageState stateFor(String id, String name, {bool assigned = false}) =>
        SendPackageState(activeDeliveryData: {
          'assignedRiderId': id,
          'assignedRiderProfile': {
            'riderId': id,
            'displayName': name,
            'rank': 'veteran',
            'rankAssigned': assigned,
            'verified': true,
            'vehicle': {'type': 'Van', 'registration': 'CIR 1'},
          },
        });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RiderCard(
          engine: stateFor('old', 'Old Rider'),
          liveStatus: 'Assigned',
          onMessage: () {},
        ),
      ),
    ));
    expect(find.text('Old Rider'), findsOneWidget);
    expect(find.byTooltip('Message Rider'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RiderCard(
          engine: stateFor('new', 'New Rider', assigned: true),
          liveStatus: 'On the way',
          terminal: true,
          onMessage: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Old Rider'), findsNothing);
    expect(find.text('New Rider'), findsOneWidget);
    expect(find.text('Assigned Veteran'), findsOneWidget);
    expect(find.byTooltip('Message Rider'), findsNothing);
  });

  test('tracking map rejects malformed and out-of-UK canonical coordinates',
      () {
    final snapshot = SenderTrackingMapAdapter.snapshotFor(
      SendPackageState(
        pickupCoordinate: PlaceCoordinate(lat: 0, lng: 0),
        desinationCoordinate: PlaceCoordinate(lat: 51.5, lng: -0.1),
      ),
      content: senderTrackingContentFor(SenderTrackingState.delivered),
      stateDelivered: true,
    );

    expect(snapshot, isNull);
  });

  test('delivered actions have receipt and post-delivery support callbacks',
      () {
    final source = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();
    expect(source, contains("? 'View receipt'"));
    expect(source, contains('? onViewReceipt'));
    expect(source, contains("? 'Get help with this delivery'"));
    expect(source, contains(': onOpenSupport'));
    expect(source,
        contains('state != SenderTrackingState.delivered && waiting.visible'));
  });

  test('Sender tracking map layer keeps GoogleMap beneath searching radar', () {
    final source = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();
    final layerStart = source.indexOf('class SenderTrackingMapLayer');
    final googleMapStart =
        source.indexOf('SenderGoogleTrackingMap(', layerStart);
    final radarStart = source.indexOf('_SearchRingsPainter(', layerStart);

    expect(layerStart, isNonNegative);
    expect(googleMapStart, greaterThan(layerStart));
    expect(radarStart, greaterThan(googleMapStart));
    expect(source.substring(layerStart, radarStart),
        contains('if (googleMapSnapshot != null)'));
  });

  test('Sender tracking action sheet intercepts platform-view hit testing', () {
    final source = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();
    final panelStart = source.indexOf('PointerInterceptor(');
    final mapStart = source.indexOf('SenderTrackingMapLayer(');

    expect(panelStart, isNonNegative);
    expect(mapStart, isNonNegative);
    expect(panelStart, greaterThan(mapStart));
    expect(
      source.substring(
        panelStart,
        source.indexOf('class _TrackingPanelContent'),
      ),
      contains('child: AppGlassContainer('),
    );
    expect(source,
        contains('Positioned.fill(\n          child: FloatingGlassPanel('));
    expect(source, contains("? 'Cancel Delivery'"));
    expect(source, contains('onTap: canCancel'));
    expect(source, contains('onCancelDelivery'));
  });

  test('Sender tracking GoogleMap is mounted before ready fade completes', () {
    final source = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();
    final mapStart = source.indexOf('class SenderGoogleTrackingMap');
    final opacityStart =
        source.indexOf('final opacity = _ready ? .88 : .01', mapStart);

    expect(mapStart, isNonNegative);
    expect(opacityStart, greaterThan(mapStart));
    expect(source.substring(mapStart),
        isNot(contains('opacity: _ready ? .88 : 0')));
  });

  test('platform view guard warns before zero-opacity attachment', () {
    final source = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();
    final mapStart = source.indexOf('class SenderGoogleTrackingMap');
    final mapSource = source.substring(mapStart);

    expect(mapStart, isNonNegative);
    expect(mapSource, contains('assertPlatformViewAttachVisibility('));
    expect(mapSource, isNot(contains('opacity: 0')));

    final guard =
        File('lib/helper/platform_view_visibility.dart').readAsStringSync();
    expect(guard, contains('opacity == 0'));
    expect(guard, contains('before attachment completed'));
    expect(guard, contains('debugPrint('));
  });

  test('all Sender GoogleMap sites use the shared platform-view guard', () {
    final tracking = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();
    final booking = File('lib/app/sender_mobile/sender_booking_canvas.dart')
        .readAsStringSync();
    final guard =
        File('lib/helper/platform_view_visibility.dart').readAsStringSync();

    expect(guard, contains('opacity == 0'));
    expect(tracking, contains('assertPlatformViewAttachVisibility('));
    expect(booking, contains('assertPlatformViewAttachVisibility('));
  });
}
