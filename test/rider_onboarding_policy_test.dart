import 'package:circum/app/rider_marketplace/rider_onboarding_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RiderOnboardingPolicy', () {
    test('pending rider cannot view or accept jobs', () {
      const profile = {'onboardingStatus': 'pending_review'};
      expect(
        RiderOnboardingPolicy.canViewJobs(
          email: 'rider@example.com',
          profile: profile,
        ),
        isFalse,
      );
      expect(
        RiderOnboardingPolicy.canAcceptJobs(
          email: 'rider@example.com',
          profile: profile,
        ),
        isFalse,
      );
    });

    test('pending rider cannot request withdrawal', () {
      expect(
        RiderOnboardingPolicy.canWithdraw(
          email: 'rider@example.com',
          profile: const {'onboardingStatus': 'pending_review'},
        ),
        isFalse,
      );
    });

    test('approved rider can access jobs after review', () {
      const profile = {'onboardingStatus': 'approved'};
      expect(
        RiderOnboardingPolicy.canAcceptJobs(
          email: 'rider@example.com',
          profile: profile,
        ),
        isTrue,
      );
      expect(
        RiderOnboardingPolicy.canWithdraw(
          email: 'rider@example.com',
          profile: profile,
        ),
        isFalse,
      );
    });

    test('approved rider can withdraw after Stripe payouts are enabled', () {
      const profile = {
        'onboardingStatus': 'approved',
        'stripeConnectAccountId': 'acct_123',
        'onboardingComplete': true,
        'payoutsEnabled': true,
        'payoutPaused': false,
      };
      expect(
        RiderOnboardingPolicy.canWithdraw(
          email: 'rider@example.com',
          profile: profile,
        ),
        isTrue,
      );
    });

    test('admin can approve rider', () {
      final patch = RiderOnboardingPolicy.adminReviewPatch(approved: true);
      expect(patch['onboardingStatus'], 'approved');
      expect(patch['riderRank'], 'agent');
    });

    test('admin can reject rider with reason', () {
      final patch = RiderOnboardingPolicy.adminReviewPatch(
        approved: false,
        rejectionReason: 'Insurance document is unclear',
      );
      expect(patch['onboardingStatus'], 'rejected');
      expect(patch['rejectionReason'], 'Insurance document is unclear');
      expect(
        () => RiderOnboardingPolicy.adminReviewPatch(approved: false),
        throwsArgumentError,
      );
    });

    test('configured super admin bypasses onboarding locks', () {
      for (final check in [
        RiderOnboardingPolicy.canViewJobs,
        RiderOnboardingPolicy.canAcceptJobs,
        RiderOnboardingPolicy.canWithdraw,
      ]) {
        expect(
          check(
            email: 'ayojason600@gmail.com',
            profile: const {'onboardingStatus': 'pending_review'},
            verifiedSuperAdmin: true,
          ),
          isTrue,
        );
      }
    });
  });
}
