import 'package:cloud_firestore/cloud_firestore.dart';

import 'iris_weight_estimator.dart';

class IrisLearningBridge {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<IrisTrustedPricingDecision> resolveWithHistory({
    required String description,
    required int quantity,
    required double userWeightKg,
  }) async {
    final estimate = IrisWeightEstimator.knownProductEstimate(description);
    if (estimate == null) {
      return IrisTrustedPricingDecision(pricingWeightKg: userWeightKg);
    }
    final itemKey = _toKey(estimate.matchedItemName);
    final historicalWeights = <double>[];
    try {
      final snapshot = await _db
          .collection('iris_learning')
          .doc(itemKey)
          .collection('records')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();
      for (final doc in snapshot.docs) {
        final value = (doc.data()['weightKg'] as num?)?.toDouble();
        if (value != null && value > 0) historicalWeights.add(value);
      }
    } catch (_) {
      // IRIS learning is best-effort; checkout must not block on history.
    }
    return IrisWeightEstimator.resolveTrustedKnownItemPricing(
      description: description,
      quantity: quantity,
      userWeightKg: userWeightKg,
      trustedItemWeightKg: estimate.singleItemWeightKg * quantity,
      historicalMatches: historicalWeights,
    );
  }

  static Future<void> recordVerifiedWeight({
    required String matchedItemName,
    required double verifiedWeightKg,
    required String source,
    String? description,
    bool riderVerified = false,
    bool disputeOccurred = false,
    bool adminOverrode = false,
  }) async {
    if (verifiedWeightKg <= 0) return;
    final estimate = IrisWeightEstimator.knownProductEstimate(
      description?.trim().isNotEmpty == true ? description! : matchedItemName,
    );
    final learningDecision = estimate == null
        ? const IrisVerifiedLearningDecision(
            canApplyToRepository: false,
            shouldCreateReviewCandidate: true,
            reasons: ['no_canonical_estimate'],
          )
        : IrisWeightEstimator.verifiedLearningDecision(
            estimate: estimate,
            finalVerifiedWeightKg: verifiedWeightKg,
            riderVerified: riderVerified,
            disputeOccurred: disputeOccurred,
            adminOverrode: adminOverrode,
          );
    try {
      final payload = {
        'matchedItemName': matchedItemName,
        'description': description,
        'weightKg': verifiedWeightKg,
        'source': source,
        'riderVerified': riderVerified,
        'disputeOccurred': disputeOccurred,
        'adminOverrode': adminOverrode,
        'learningApplied': learningDecision.canApplyToRepository,
        'reviewReasons': learningDecision.reasons,
        'timestamp': FieldValue.serverTimestamp(),
      };
      if (learningDecision.canApplyToRepository) {
        await _db
            .collection('iris_learning')
            .doc(_toKey(matchedItemName))
            .collection('records')
            .add(payload);
      } else {
        await _db.collection('iris_learning_review_candidates').add(payload);
      }
    } catch (_) {
      // Learning records are append-only and best-effort.
    }
  }

  static String _toKey(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}
