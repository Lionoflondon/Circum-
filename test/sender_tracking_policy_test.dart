import 'package:circum/app/delivery/sender_tracking_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SenderTrackingPolicy', () {
    test('maps backend states to sender labels', () {
      expect(SenderTrackingPolicy.copyFor('finding_rider').label,
          'Finding a rider');
      expect(SenderTrackingPolicy.copyFor('accepted').label,
          'Rider accepted your delivery');
      expect(SenderTrackingPolicy.copyFor('navigating_to_pickup').label,
          'Rider on the way to pickup');
      expect(SenderTrackingPolicy.copyFor('arrived_at_pickup').label,
          'Your rider is outside');
      expect(SenderTrackingPolicy.copyFor('waiting').label, 'Rider is waiting');
      expect(SenderTrackingPolicy.copyFor('pickup_verification').label,
          'Verifying your parcel');
      expect(SenderTrackingPolicy.copyFor('pickup_verified').label,
          'Parcel verified');
      expect(
          SenderTrackingPolicy.copyFor('collected').label, 'Parcel collected');
      expect(SenderTrackingPolicy.copyFor('navigating_to_dropoff').label,
          'On the way to drop-off');
      expect(SenderTrackingPolicy.copyFor('arrived_at_dropoff').label,
          'Rider has arrived at drop-off');
      expect(SenderTrackingPolicy.copyFor('pin_required').label,
          'PIN required to complete delivery');
      expect(SenderTrackingPolicy.copyFor('delivered').label, 'Delivered');
    });

    test('issue reported keeps reassuring update copy', () {
      final copy = SenderTrackingPolicy.copyFor('issue_reported');
      expect(copy.label, 'Delivery update');
      expect(copy.body, contains('already assisting your rider'));
    });

    test('timeline index follows delivery progress', () {
      expect(SenderTrackingPolicy.timelineIndex('finding_rider'), 0);
      expect(SenderTrackingPolicy.timelineIndex('arrived_at_pickup'), 1);
      expect(SenderTrackingPolicy.timelineIndex('collected'), 2);
      expect(SenderTrackingPolicy.timelineIndex('navigating_to_dropoff'), 3);
      expect(
          SenderTrackingPolicy.timelineIndex('pin_required', collected: true),
          3);
      expect(SenderTrackingPolicy.timelineIndex('delivered'), 4);
    });

    test('badge priority favours Vanguard then Health+ then Gift', () {
      expect(
        SenderTrackingPolicy.badgeFor({
          'vanguardProtocolEnabled': true,
          'isHealthPlus': true,
          'isGift': true,
        }),
        SenderTrackingBadge.vanguard,
      );
      expect(
        SenderTrackingPolicy.badgeFor({'isHealthPlus': true, 'isGift': true}),
        SenderTrackingBadge.healthPlus,
      );
      expect(
        SenderTrackingPolicy.badgeFor({'isGift': true}),
        SenderTrackingBadge.gift,
      );
    });

    test('sender timeline reflects Vanguard protocol lifecycle', () {
      final delivery = {
        'vanguardProtocolEnabled': true,
        'vanguardStatus': 'secure_custody',
      };

      expect(SenderTrackingPolicy.shouldShowVanguardTimeline(delivery), isTrue);
      expect(
        SenderTrackingPolicy.vanguardTimeline(delivery),
        [
          'Vanguard pickup verification',
          'Secure custody',
          'Secure transit',
          'Secure handover',
        ],
      );
      expect(
        SenderTrackingPolicy.vanguardStatusLabel(delivery),
        'Secure custody active',
      );
    });

    test('rider card is absent while finding rider', () {
      expect(SenderTrackingPolicy.isFindingRider('finding_rider'), true);
      expect(SenderTrackingPolicy.isFindingRider('accepted'), false);
    });

    test('waiting card appears only for arrival or backend wait state', () {
      expect(
          SenderTrackingPolicy.shouldShowWaitingCard(
              'arrived_at_pickup', false),
          true);
      expect(
          SenderTrackingPolicy.shouldShowWaitingCard(
              'arrived_at_dropoff', false),
          true);
      expect(SenderTrackingPolicy.shouldShowWaitingCard('waiting', true), true);
      expect(
          SenderTrackingPolicy.shouldShowWaitingCard('waiting', false), false);
      expect(
          SenderTrackingPolicy.shouldShowWaitingCard('accepted', true), false);
    });

    test('pickup pin state shows collection PIN before collection', () {
      expect(
          SenderTrackingPolicy.showCollectionPin({
            'status': 'pin_required',
            'collectionPin': '4271',
          }),
          true);
      expect(
          SenderTrackingPolicy.showDeliveryPinNotice({
            'status': 'pin_required',
            'collectionPin': '4271',
          }),
          false);
    });

    test(
        'drop-off pin state shows receiver delivery PIN notice after collection',
        () {
      expect(
          SenderTrackingPolicy.showCollectionPin({
            'status': 'pin_required',
            'collectionPinVerified': true,
            'deliveryPin': '8352',
          }),
          false);
      expect(
          SenderTrackingPolicy.showDeliveryPinNotice({
            'status': 'pin_required',
            'collectionPinVerified': true,
            'deliveryPin': '8352',
          }),
          true);
    });
  });
}
