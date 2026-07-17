import 'dart:io';

import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender mobile preserves distinct pickup and drop-off coordinates', () {
    final source = File('lib/app/send_package/bloc/send_package_bloc.dart')
        .readAsStringSync();

    expect(
      source,
      contains(
        "'lat': event.dropoffDetails.address.lat,\n"
        "            'lng': event.dropoffDetails.address.lng",
      ),
    );
    expect(
      source,
      isNot(
        contains(
          "'lat': event.dropoffDetails.address.lat,\n"
          "            'lng': event.pickupDetails.address.lng",
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

  test('Sender mobile normalizes backend tracking fields like Sender Web', () {
    expect(
      backendStatusFromDelivery({
        'status': 'accepted',
        'trackingStatus': 'out_for_delivery',
        'deliveryStatus': 'arrived_at_dropoff',
        'deliveryStage': 'Pin Required',
      }),
      'pin_required',
    );

    expect(
      senderTrackingStageForBackendStatus(' navigating-to-pickup '),
      SenderTrackingStage.riderEnRouteToPickup,
    );
    expect(
      senderTrackingStageForBackendStatus('ARRIVED AT PICKUP'),
      SenderTrackingStage.riderArrivedAtPickup,
    );
    expect(
      senderTrackingStageForBackendStatus('pickup_verified'),
      SenderTrackingStage.pickupComplete,
    );
    expect(
      senderTrackingStageForBackendStatus('outForDelivery'),
      SenderTrackingStage.inTransit,
    );
    expect(
      senderTrackingStageForBackendStatus('pin-required'),
      SenderTrackingStage.riderArrivingAtDropoff,
    );
    expect(
      senderTrackingStageForBackendStatus('sender_no_show_pickup'),
      SenderTrackingStage.cancelled,
    );
    expect(
      senderTrackingStageForBackendStatus('issue_reported'),
      SenderTrackingStage.issue,
    );
    expect(
      senderTrackingStageForBackendStatus('unknown_future_status'),
      SenderTrackingStage.inTransit,
    );
  });

  test('Sender mobile contains user-facing copy for every tracking stage', () {
    for (final stage in SenderTrackingStage.values) {
      expect(senderTrackingCopy[stage], isNotNull);
      expect(senderTrackingCopy[stage]!.title.trim(), isNotEmpty);
      expect(senderTrackingCopy[stage]!.body.trim(), isNotEmpty);
    }

    expect(
      senderTrackingCopy[SenderTrackingStage.riderArrivingAtDropoff]!.title,
      'Arrived at drop-off',
    );
  });

  test('Sender mobile does not expose receiver-only delivery PIN fields', () {
    final data = {
      'deliveryStage': 'arrived_at_dropoff',
      'deliveryPin': '111111',
      'receiverPin': '222222',
      'dropoffPin': '333333',
    };

    expect(senderVisiblePinFromDelivery(data), isNull);

    expect(
      senderVisiblePinFromDelivery({
        ...data,
        'senderVisiblePin': '444444',
      }),
      '444444',
    );

    expect(
      senderVisiblePinFromDelivery({
        ...data,
        'deliveryStage': 'delivered',
        'senderVisiblePin': '444444',
      }),
      isNull,
    );
  });

  test('Sender mobile active panel renders stage-specific tracking content',
      () {
    final source = File(
      'lib/app/send_package/view/parts/active_delivery_details.dart',
    ).readAsStringSync();

    expect(source, contains('trackingCopy.title'));
    expect(source, contains('trackingCopy.body'));
    expect(source, contains('SenderTrackingStage.findingRider'));
    expect(source, contains('SenderTrackingStage.riderArrivingAtDropoff'));
    expect(source, contains('state.senderVisiblePin'));
  });
}
