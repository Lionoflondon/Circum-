import 'package:circum/app/rider_jobs/rider_home_state_mapper.dart';
import 'package:circum/app/rider_jobs/rider_job_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RiderHomeStateMapper', () {
    test('maps approval and online states without coupling UI to raw strings',
        () {
      expect(
        RiderHomeStateMapper.fromBackend(riderProfile: null),
        RiderJobUiState.pendingApproval,
      );
      expect(
        RiderHomeStateMapper.fromBackend(
          riderProfile: {'onboardingStatus': 'approved', 'isOnline': false},
        ),
        RiderJobUiState.offline,
      );
      expect(
        RiderHomeStateMapper.fromBackend(
          riderProfile: {'onboardingStatus': 'approved', 'isOnline': true},
        ),
        RiderJobUiState.onlineWaiting,
      );
      expect(
        RiderHomeStateMapper.fromBackend(
          riderProfile: {'onboardingStatus': 'approved'},
          hasAvailableOffers: true,
        ),
        RiderJobUiState.offline,
      );
      expect(
        RiderHomeStateMapper.fromBackend(
          riderProfile: {'onboardingStatus': 'approved'},
          presence: {
            'isOnline': true,
            'availabilityStatus': 'available',
          },
          hasAvailableOffers: true,
        ),
        RiderJobUiState.offerAvailable,
      );
    });

    test('maps operational delivery states to presentation states', () {
      final approved = {'onboardingStatus': 'approved'};
      expect(
        RiderHomeStateMapper.fromBackend(
          riderProfile: approved,
          activeDelivery: {'status': 'navigating_to_pickup'},
        ),
        RiderJobUiState.navigatingToPickup,
      );
      expect(
        RiderHomeStateMapper.fromBackend(
          riderProfile: approved,
          activeDelivery: {'status': 'pickup_verification'},
        ),
        RiderJobUiState.verification,
      );
      expect(
        RiderHomeStateMapper.fromBackend(
          riderProfile: approved,
          activeDelivery: {'status': 'issue_reported'},
        ),
        RiderJobUiState.deliveryUpdate,
      );
    });

    test('delivery update uses calm non-destructive copy', () {
      final copy = RiderHomeStateMapper.copyFor(RiderJobUiState.deliveryUpdate);
      expect(copy, contains('Support has already been notified'));
      expect(copy, isNot(contains('cancel')));
      expect(copy, isNot(contains('decline')));
    });

    test('busy presence blocks offers and surfaces active delivery state', () {
      expect(
        RiderHomeStateMapper.fromBackend(
          riderProfile: {'onboardingStatus': 'approved'},
          presence: {
            'isOnline': true,
            'availabilityStatus': 'busy',
            'activeDeliveryId': 'delivery-1',
          },
          hasAvailableOffers: true,
        ),
        RiderJobUiState.accepted,
      );
    });
  });
}
