import 'package:circum/app/rider_jobs/rider_accept_controller.dart';
import 'package:circum/app/rider_jobs/rider_job_models.dart';
import 'package:circum/app/rider_jobs/rider_offer_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Rider offer flow', () {
    test('swiping has no backend mutation hook', () {
      expect(RiderAcceptController.swipeMutatesBackend(), false);
    });

    test('accept patch is first-rider-wins and blocks second accept', () {
      final fresh = {'status': 'requested', 'matchingStatus': 'available'};
      final patch = RiderAcceptController.acceptancePatchForFreshJob(
        job: fresh,
        riderId: 'rider-1',
        riderName: 'Jason',
        vehicle: 'Bike',
      );
      expect(patch, isNotNull);
      expect(patch!['status'], 'accepted');
      expect(patch['riderId'], 'rider-1');

      final alreadyAssigned = {
        'status': 'accepted',
        'matchingStatus': 'accepted',
        'riderId': 'rider-1',
      };
      expect(
        RiderAcceptController.acceptancePatchForFreshJob(
          job: alreadyAssigned,
          riderId: 'rider-2',
          riderName: 'Ayo',
        ),
        isNull,
      );
    });

    test('Vanguard protocol flag marks rider offer as Vanguard', () {
      final offer = RiderJobOffer.fromMap({
        'id': 'vanguard-protocol-job',
        'estimatedEarnings': 18.5,
        'pickupArea': 'Mayfair',
        'dropoffArea': 'Chelsea',
        'vanguardProtocolEnabled': true,
        'vanguardStatus': 'secure_custody',
      });

      expect(offer.categories, contains(RiderJobCategory.vanguard));
      expect(offer.warningChips, contains('Vanguard'));
    });

    testWidgets('offer card has Accept only and no Roth/reject/decline copy',
        (tester) async {
      final offer = RiderJobOffer(
        id: 'offer-1',
        estimatedEarnings: 14.80,
        pickupArea: 'Marylebone',
        dropoffArea: 'Chelsea',
        distanceLabel: '3.4 mi',
        etaLabel: '22 min',
        parcelSummary: 'Prescription box · Vanguard included',
        vehicleLabel: 'Bike',
        weightLabel: '0.2kg',
        pickupTimingLabel: 'ASAP',
        riderRank: 'Sentinel',
        categories: const {
          RiderJobCategory.healthPlus,
          RiderJobCategory.vanguard,
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: RiderOfferCard(offer: offer, onAccept: () {}),
          ),
        ),
      );
      expect(find.text('Accept Delivery'), findsOneWidget);
      expect(find.textContaining('Roth'), findsNothing);
      expect(find.textContaining('Reject'), findsNothing);
      expect(find.textContaining('Decline'), findsNothing);
    });
  });
}
