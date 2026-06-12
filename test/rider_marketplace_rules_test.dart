import 'package:circum/app/rider_marketplace/rider_marketplace_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RiderMarketplaceRules', () {
    test('first accepted rider gets assigned', () {
      final patch = RiderMarketplaceRules.firstAcceptancePatch(
        job: const {
          'status': 'requested',
          'matchingStatus': 'available',
        },
        riderId: 'rider-1',
        riderName: 'Ayo Rider',
        vehicle: 'Van',
        plateNumber: 'CIR 123',
      );

      expect(patch, isNotNull);
      expect(patch!['riderId'], 'rider-1');
      expect(patch['status'], 'accepted');
      expect(patch['matchingStatus'], 'accepted');
    });

    test('later acceptance is blocked once a job is assigned', () {
      final patch = RiderMarketplaceRules.firstAcceptancePatch(
        job: const {
          'status': 'accepted',
          'matchingStatus': 'accepted',
          'riderId': 'rider-1',
        },
        riderId: 'rider-2',
        riderName: 'Late Rider',
      );

      expect(patch, isNull);
    });

    test('rider can reject or ignore jobs', () {
      expect(
        RiderMarketplaceRules.riderDecisionPatch(
          riderId: 'rider-1',
          decision: 'reject',
        )['rejectedByRiders'],
        contains('rider-1'),
      );
      expect(
        RiderMarketplaceRules.riderDecisionPatch(
          riderId: 'rider-1',
          decision: 'ignore',
        )['ignoredByRiders'],
        contains('rider-1'),
      );
    });

    test('wallet transaction amount includes delivery earning and tip', () {
      expect(
        RiderMarketplaceRules.walletCreditForCompletedJob(
          deliveryEarning: 9.15,
          tipAmount: 2,
        ),
        11.15,
      );
    });

    test('withdrawal request prevents duplicates', () {
      expect(
        RiderMarketplaceRules.canRequestWithdrawal(
          amount: 20,
          availableBalance: 25,
          hasPendingWithdrawal: false,
        ),
        isTrue,
      );
      expect(
        RiderMarketplaceRules.canRequestWithdrawal(
          amount: 20,
          availableBalance: 25,
          hasPendingWithdrawal: true,
        ),
        isFalse,
      );
    });

    test('earning transaction id is deterministic for idempotency', () {
      expect(
        RiderMarketplaceRules.earningTransactionId(
          deliveryId: 'delivery-1',
          riderId: 'rider-1',
        ),
        'delivery-1_rider-1_completion',
      );
    });

    test('total owed equals pending plus available balances', () {
      expect(
        RiderMarketplaceRules.totalRiderLiability(const [
          {'pendingBalance': 12.5, 'availableBalance': 7.5},
          {'pendingBalance': 3, 'availableBalance': 2},
        ]),
        25,
      );
    });

    test('withdrawal cannot exceed available balance', () {
      expect(
        RiderMarketplaceRules.canRequestWithdrawal(
          amount: 30,
          availableBalance: 25,
          hasPendingWithdrawal: false,
        ),
        isFalse,
      );
    });
  });
}
