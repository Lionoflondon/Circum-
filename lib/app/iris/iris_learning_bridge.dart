import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'iris_weight_estimator.dart';

class IrisLearningBridge {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

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
    try {
      final payload = {
        'matchedItemName': matchedItemName,
        'description': description,
        'userCorrectedWeightKg': verifiedWeightKg,
        'source': source,
        'riderVerified': riderVerified,
        'disputeOccurred': disputeOccurred,
        'adminOverrode': adminOverrode,
        'learningApplied': false,
        'reviewReasons': ['canonical_review_required'],
      };
      await _functions
          .httpsCallable('recordIrisLearningCandidate')
          .call(payload);
    } catch (_) {
      // Learning records are append-only and best-effort.
    }
  }

  static String _toKey(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}
