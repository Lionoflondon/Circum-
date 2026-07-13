import 'dart:io';

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

    test('rider waiting actions use backend callables and delivery chat', () {
      final source =
          File('lib/app/rider_jobs/rider_home_screen.dart').readAsStringSync();

      expect(source, contains('Customer Responded'));
      expect(source, contains('Mark No-show'));
      expect(source, contains('markCustomerResponded'));
      expect(source, contains('recordCustomerResponded'));
      expect(source, contains('markSenderNoShow'));
      expect(source, contains('declareSenderNoShow'));
      expect(source, contains('sendRiderUpdate'));
      expect(source, contains('RideChatPageView(chatId: chatId)'));
      expect(source,
          contains('Missed collection unlocks when the waiting period'));
    });

    test('active delivery restores before dashboard after refresh', () {
      final source =
          File('lib/app/rider_jobs/rider_home_screen.dart').readAsStringSync();

      expect(source, contains('_activeDeliveryCacheKey'));
      expect(source, contains('_restoreActiveDeliveryCache'));
      expect(source, contains('_cacheActiveDelivery'));
      expect(source, contains('_clearActiveDeliveryCache'));
      expect(source, contains('backendActiveDelivery ??'));
      expect(source, contains('_cachedActiveDelivery'));
      expect(source, contains('class _ActiveDeliveryPane'));
      final activeBranch = source.substring(
        source.indexOf('child: activeDelivery !='),
        source.indexOf('class _DashboardPane'),
      );
      expect(
        activeBranch.indexOf('_ActiveDeliveryPane'),
        lessThan(activeBranch.indexOf('_OffersPane')),
      );
      expect(source, contains('Restored from your current assignment.'));
      expect(source, isNot(contains('Backend updates run in production')));
    });
  });
}
