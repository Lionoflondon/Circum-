import 'package:cloud_functions/cloud_functions.dart';

import '../rider_marketplace/rider_marketplace_rules.dart';
import '../rider_marketplace/rider_onboarding_policy.dart';

class RiderAcceptResult {
  final bool accepted;
  final String message;

  const RiderAcceptResult._({
    required this.accepted,
    required this.message,
  });

  const RiderAcceptResult.accepted()
      : this._(accepted: true, message: 'Delivery accepted.');

  const RiderAcceptResult.alreadyAccepted()
      : this._(
          accepted: false,
          message: 'This delivery has already been accepted.',
        );

  const RiderAcceptResult.blocked(String reason)
      : this._(accepted: false, message: reason);
}

class RiderAcceptController {
  final FirebaseFunctions functions;

  RiderAcceptController({FirebaseFunctions? functions})
      : functions = functions ?? FirebaseFunctions.instance;

  bool canStartAccept({
    required String? email,
    required Map<String, dynamic>? riderProfile,
    bool verifiedSuperAdmin = false,
  }) {
    return RiderOnboardingPolicy.canAcceptJobs(
      email: email,
      profile: riderProfile,
      verifiedSuperAdmin: verifiedSuperAdmin,
    );
  }

  Future<RiderAcceptResult> acceptDelivery({
    required String deliveryId,
    required String riderId,
    required String riderName,
    required String? email,
    required Map<String, dynamic>? riderProfile,
    bool verifiedSuperAdmin = false,
    String? vehicle,
    String? plateNumber,
  }) async {
    if (!canStartAccept(
      email: email,
      riderProfile: riderProfile,
      verifiedSuperAdmin: verifiedSuperAdmin,
    )) {
      return const RiderAcceptResult.blocked(
        'Complete rider approval before accepting deliveries.',
      );
    }

    try {
      await functions.httpsCallable('acceptRideRequests').call({
        'requestId': deliveryId,
      });
      return const RiderAcceptResult.accepted();
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'already-exists') {
        return const RiderAcceptResult.alreadyAccepted();
      }
      return RiderAcceptResult.blocked(
        error.message ?? 'Unable to accept this delivery.',
      );
    } catch (_) {
      return const RiderAcceptResult.blocked('Unable to accept this delivery.');
    }
  }

  static Map<String, dynamic>? acceptancePatchForFreshJob({
    required Map<String, dynamic> job,
    required String riderId,
    required String riderName,
    String? vehicle,
    String? plateNumber,
  }) {
    return RiderMarketplaceRules.firstAcceptancePatch(
      job: job,
      riderId: riderId,
      riderName: riderName,
      vehicle: vehicle,
      plateNumber: plateNumber,
    );
  }

  static bool swipeMutatesBackend() => false;
}
