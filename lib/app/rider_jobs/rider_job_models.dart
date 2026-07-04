import 'package:flutter/foundation.dart';

enum RiderJobCategory {
  standard,
  marketplace,
  business,
  vanguard,
  heavyDuty,
  gift,
  scheduled,
  healthPlus,
}

enum RiderJobUiState {
  loading,
  pendingApproval,
  offline,
  goingOnline,
  onlineWaiting,
  offerAvailable,
  accepted,
  navigatingToPickup,
  arrivedWaiting,
  verification,
  inTransit,
  completed,
  deliveryUpdate,
}

@immutable
class RiderJobOffer {
  final String id;
  final double estimatedEarnings;
  final String pickupArea;
  final String dropoffArea;
  final String distanceLabel;
  final String etaLabel;
  final String parcelSummary;
  final String vehicleLabel;
  final String weightLabel;
  final String pickupTimingLabel;
  final String riderRank;
  final DateTime? expiresAt;
  final Set<RiderJobCategory> categories;
  final List<String> warningChips;
  final Map<String, dynamic> raw;

  const RiderJobOffer({
    required this.id,
    required this.estimatedEarnings,
    required this.pickupArea,
    required this.dropoffArea,
    required this.distanceLabel,
    required this.etaLabel,
    required this.parcelSummary,
    required this.vehicleLabel,
    required this.weightLabel,
    required this.pickupTimingLabel,
    required this.riderRank,
    this.expiresAt,
    this.categories = const {},
    this.warningChips = const [],
    this.raw = const {},
  });

  factory RiderJobOffer.fromMap(Map<String, dynamic> data) {
    final pickup = data['pickupAddress'] is Map
        ? (data['pickupAddress'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final dropoff = data['dropoffAddress'] is Map
        ? (data['dropoffAddress'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return RiderJobOffer(
      id: '${data['id'] ?? data['_docId'] ?? ''}',
      estimatedEarnings:
          ((data['riderEarning'] ?? data['estimatedEarnings'] ?? 0) as num)
              .toDouble(),
      pickupArea:
          '${pickup['area'] ?? pickup['city'] ?? data['pickupArea'] ?? 'Pickup'}',
      dropoffArea:
          '${dropoff['area'] ?? dropoff['city'] ?? data['dropoffArea'] ?? 'Drop-off'}',
      distanceLabel: '${data['distanceLabel'] ?? data['distance'] ?? '--'}',
      etaLabel: '${data['etaLabel'] ?? data['estimatedDuration'] ?? '--'}',
      parcelSummary:
          '${data['parcelSummary'] ?? data['itemDescription'] ?? 'Parcel'}',
      vehicleLabel:
          '${data['recommendedVehicle'] ?? data['minimumVehicle'] ?? 'Vehicle'}',
      weightLabel: '${data['weightLabel'] ?? data['weightKg'] ?? '--'}',
      pickupTimingLabel:
          '${data['pickupTiming'] ?? data['pickupTimingLabel'] ?? 'ASAP'}',
      riderRank: '${data['riderRank'] ?? 'Sentinel'}',
      expiresAt:
          data['expiresAt'] is DateTime ? data['expiresAt'] as DateTime : null,
      categories: RiderJobCategoryRules.categoriesFromJob(data),
      warningChips: [
        if (data['isVanguard'] == true) 'Vanguard',
        if (data['isHealthPlus'] == true) 'Health+',
        if (data['isHeavyDuty'] == true) 'Heavy',
        if (data['isScheduled'] == true) 'Scheduled',
      ],
      raw: data,
    );
  }
}

class RiderJobCategoryRules {
  static Set<RiderJobCategory> categoriesFromJob(Map<String, dynamic> job) {
    final categories = <RiderJobCategory>{};
    if (job['isHealthPlus'] == true || job['healthPlus'] == true) {
      categories.add(RiderJobCategory.healthPlus);
    }
    if (job['isGift'] == true || job['giftDelivery'] == true) {
      categories.add(RiderJobCategory.gift);
    }
    if (job['isScheduled'] == true || job['scheduledAt'] != null) {
      categories.add(RiderJobCategory.scheduled);
    }
    if (job['isVanguard'] == true || job['requiresVanguard'] == true) {
      categories.add(RiderJobCategory.vanguard);
    }
    if (job['isBusiness'] == true || job['businessDelivery'] == true) {
      categories.add(RiderJobCategory.business);
    }
    if (job['isMarketplace'] == true || job['marketplace'] == true) {
      categories.add(RiderJobCategory.marketplace);
    }
    if (job['isHeavyDuty'] == true || job['heavyDuty'] == true) {
      categories.add(RiderJobCategory.heavyDuty);
    }
    return categories;
  }
}
