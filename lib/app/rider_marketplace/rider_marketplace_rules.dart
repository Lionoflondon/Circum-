class RiderMarketplaceRules {
  static bool canAcceptJob(Map<String, dynamic> job) {
    final status = '${job['status'] ?? 'requested'}'.toLowerCase();
    final matchingStatus =
        '${job['matchingStatus'] ?? 'available'}'.toLowerCase();
    final assignedRider =
        '${job['riderId'] ?? job['driverId'] ?? job['assignedDriverId'] ?? ''}'
            .trim();
    return assignedRider.isEmpty &&
        status == 'requested' &&
        (matchingStatus == 'available' || matchingStatus == 'requested');
  }

  static Map<String, dynamic>? firstAcceptancePatch({
    required Map<String, dynamic> job,
    required String riderId,
    required String riderName,
    String? vehicle,
    String? plateNumber,
  }) {
    if (!canAcceptJob(job)) return null;
    return {
      'riderId': riderId,
      'driverId': riderId,
      'assignedDriverId': riderId,
      'riderName': riderName,
      'driverName': riderName,
      'driverVehicle': vehicle,
      'driverPlateNumber': plateNumber,
      'status': 'accepted',
      'dispatchStatus': 'accepted',
      'matchingStatus': 'accepted',
    };
  }

  static Map<String, dynamic> riderDecisionPatch({
    required String riderId,
    required String decision,
    List<dynamic> existingRiders = const [],
  }) {
    final field = decision == 'reject' ? 'rejectedByRiders' : 'ignoredByRiders';
    return {
      field: {...existingRiders, riderId}.toList(),
    };
  }

  static double walletCreditForCompletedJob({
    required double deliveryEarning,
    double tipAmount = 0,
  }) {
    return double.parse((deliveryEarning + tipAmount).toStringAsFixed(2));
  }

  static String earningTransactionId({
    required String deliveryId,
    required String riderId,
  }) {
    return '${deliveryId}_${riderId}_completion';
  }

  static double totalRiderLiability(Iterable<Map<String, dynamic>> wallets) {
    return wallets.fold<double>(0, (total, wallet) {
      final pending = (wallet['pendingBalance'] as num?)?.toDouble() ?? 0;
      final available = (wallet['availableBalance'] as num?)?.toDouble() ?? 0;
      return total + pending + available;
    });
  }

  static bool canRequestWithdrawal({
    required double amount,
    required double availableBalance,
    required bool hasPendingWithdrawal,
  }) {
    return amount > 0 && amount <= availableBalance && !hasPendingWithdrawal;
  }
}
