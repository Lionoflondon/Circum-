import 'package:cloud_firestore/cloud_firestore.dart';

class SenderProfile {
  final String id;
  final String fullName;
  final String email;
  final String phoneNumber;
  final String photoUrl;
  final String verificationStatus;
  final DateTime? createdAt;
  final List<SavedSenderAddress> savedAddresses;
  final List<SavedRecipient> savedRecipients;
  final Map<String, dynamic> communicationPreferences;
  final String? paymentCustomerReference;
  final bool isLegend;
  final int? legendNumber;
  final DateTime? legendAwardedAt;
  final DateTime? legendCelebrationSeenAt;
  final int trustPoints;
  final String senderTier;
  final bool senderTrustFrozen;
  final Map<String, dynamic> senderTrustBreakdown;

  const SenderProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.photoUrl,
    required this.verificationStatus,
    required this.createdAt,
    this.savedAddresses = const [],
    this.savedRecipients = const [],
    this.communicationPreferences = const {},
    this.paymentCustomerReference,
    this.isLegend = false,
    this.legendNumber,
    this.legendAwardedAt,
    this.legendCelebrationSeenAt,
    this.trustPoints = 0,
    this.senderTier = 'new_sender',
    this.senderTrustFrozen = false,
    this.senderTrustBreakdown = const {},
  });

  factory SenderProfile.fromMap(String id, Map<String, dynamic> data) {
    return SenderProfile(
      id: id,
      fullName: '${data['fullName'] ?? data['fullname'] ?? data['name'] ?? ''}',
      email: '${data['email'] ?? ''}',
      phoneNumber: '${data['phoneNumber'] ?? data['phone'] ?? ''}',
      photoUrl:
          '${data['photoURL'] ?? data['photoUrl'] ?? data['image'] ?? ''}',
      verificationStatus:
          '${data['verificationStatus'] ?? data['accountStatus'] ?? 'unverified'}',
      createdAt: parseDate(data['createdAt']),
      savedAddresses: (data['savedAddresses'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SavedSenderAddress.fromMap)
          .toList(growable: false),
      savedRecipients: (data['savedRecipients'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SavedRecipient.fromMap)
          .toList(growable: false),
      communicationPreferences:
          Map<String, dynamic>.from(data['communicationPreferences'] ?? {}),
      paymentCustomerReference: data['customerId'] == null
          ? null
          : SenderProfileService.sanitizedPaymentReference(
              '${data['customerId']}'),
      isLegend: data['isLegend'] == true,
      legendNumber: (data['legendNumber'] as num?)?.toInt(),
      legendAwardedAt: parseDate(data['legendAwardedAt']),
      legendCelebrationSeenAt: parseDate(data['legendCelebrationSeenAt']),
      trustPoints: (data['senderTrustPoints'] as num?)?.toInt() ??
          (data['trustPoints'] as num?)?.toInt() ??
          0,
      senderTier: SenderTrustPolicy.normalizeTier(
        data['senderTier'] ?? data['trustTier'],
        points: (data['senderTrustPoints'] as num?)?.toInt() ??
            (data['trustPoints'] as num?)?.toInt() ??
            0,
      ),
      senderTrustFrozen: data['senderTrustFrozen'] == true,
      senderTrustBreakdown:
          Map<String, dynamic>.from(data['senderTrustBreakdown'] ?? {}),
    );
  }

  Map<String, dynamic> safeUpdatePatch({
    required String fullName,
    required String phoneNumber,
    required List<SavedSenderAddress> savedAddresses,
    required Map<String, dynamic> communicationPreferences,
  }) {
    return {
      'fullName': fullName.trim(),
      'fullname': fullName.trim(),
      'phoneNumber': phoneNumber.trim(),
      'savedAddresses':
          savedAddresses.map((address) => address.toJson()).toList(),
      'communicationPreferences': communicationPreferences,
      'userType': 'sender',
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class SenderTrustPolicy {
  static const tiers = [
    'new_sender',
    'active_sender',
    'regular_sender',
    'priority_sender',
    'platinum_sender',
  ];

  static const tierLabels = {
    'new_sender': 'New Sender',
    'active_sender': 'Active Sender',
    'regular_sender': 'Regular Sender',
    'priority_sender': 'Priority Sender',
    'platinum_sender': 'Platinum Sender',
  };

  static const thresholds = {
    'new_sender': 0,
    'active_sender': 25,
    'regular_sender': 100,
    'priority_sender': 300,
    'platinum_sender': 750,
  };

  static const pointRules = {
    'parcel_sent': 1,
    'successful_delivery': 1,
    'lifetime_spend_milestone': 2,
    'gifts_order': 3,
    'health_order': 5,
    'account_age_milestone': 2,
    'referral': 7,
    'confirmed_fraud': -5,
    'wrong_chargeback': -4,
    'unnecessary_cancellation': -3,
  };

  static String tierForPoints(int points) {
    if (points >= 750) return 'platinum_sender';
    if (points >= 300) return 'priority_sender';
    if (points >= 100) return 'regular_sender';
    if (points >= 25) return 'active_sender';
    return 'new_sender';
  }

  static String normalizeTier(Object? value, {int points = 0}) {
    final raw =
        '$value'.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return tiers.contains(raw) ? raw : tierForPoints(points);
  }

  static String label(Object? tierOrPoints) {
    if (tierOrPoints is num) {
      return tierLabels[tierForPoints(tierOrPoints.toInt())]!;
    }
    final tier = normalizeTier(tierOrPoints);
    return tierLabels[tier] ?? 'New Sender';
  }

  static String? nextTier(String tier) {
    final normalized = normalizeTier(tier);
    final index = tiers.indexOf(normalized);
    if (index < 0 || index >= tiers.length - 1) return null;
    return tiers[index + 1];
  }

  static int pointsForNextTier(int points) {
    final next = nextTier(tierForPoints(points));
    if (next == null) return 0;
    return (thresholds[next] ?? points) - points;
  }

  static bool isPositiveEvent(String eventType, int points) {
    return points > 0 &&
        !eventType.toLowerCase().contains('deduct') &&
        !eventType.toLowerCase().contains('fraud') &&
        !eventType.toLowerCase().contains('chargeback');
  }
}

class SavedSenderAddress {
  final String label;
  final String address;
  final String addressType;
  final String notes;
  final String? postcode;
  final double? lat;
  final double? lng;
  final String? placeId;
  final String? provider;
  final String? locationId;

  const SavedSenderAddress({
    required this.label,
    required this.address,
    this.addressType = 'pickup',
    this.notes = '',
    this.postcode,
    this.lat,
    this.lng,
    this.placeId,
    this.provider,
    this.locationId,
  });

  factory SavedSenderAddress.fromMap(Map<String, dynamic> data) {
    return SavedSenderAddress(
      label: '${data['label'] ?? 'Saved address'}',
      address: '${data['address'] ?? ''}',
      addressType:
          '${data['addressType'] ?? data['type'] ?? data['usage'] ?? 'pickup'}',
      notes: '${data['notes'] ?? data['moreInformation'] ?? ''}',
      postcode: data['postcode'] == null ? null : '${data['postcode']}',
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      placeId: data['placeId'] == null ? null : '${data['placeId']}',
      provider: data['provider'] == null ? null : '${data['provider']}',
      locationId: data['locationId'] == null ? null : '${data['locationId']}',
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'address': address,
        'addressType': addressType,
        if (notes.trim().isNotEmpty) 'notes': notes,
        if (postcode?.trim().isNotEmpty == true) 'postcode': postcode,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (placeId?.trim().isNotEmpty == true) 'placeId': placeId,
        if (provider?.trim().isNotEmpty == true) 'provider': provider,
        if (locationId?.trim().isNotEmpty == true) 'locationId': locationId,
      };
}

class SavedRecipient {
  final String fullName;
  final String phoneNumber;
  final String address;

  const SavedRecipient({
    required this.fullName,
    required this.phoneNumber,
    required this.address,
  });

  factory SavedRecipient.fromMap(Map<String, dynamic> data) {
    return SavedRecipient(
      fullName: '${data['fullName'] ?? data['fullname'] ?? data['name'] ?? ''}',
      phoneNumber: '${data['phoneNumber'] ?? data['phone'] ?? ''}',
      address: '${data['address'] ?? ''}',
    );
  }
}

class SenderDeliveryRecord {
  final String id;
  final String senderId;
  final String requestId;
  final String parcelDescription;
  final String pickupAddress;
  final String dropoffAddress;
  final DateTime? createdAt;
  final String status;
  final String serviceType;
  final String assignedDriverName;
  final String assignedDriverPhone;
  final String assignedDriverPhotoUrl;
  final String assignedDriverVehicle;
  final double pricePaid;
  final String currency;
  final String paymentStatus;
  final String trackingReference;
  final String irisMatchedItemName;
  final double parcelWeightKg;
  final String weightBand;
  final String recommendedVehicle;
  final bool fragile;
  final String handlingNotes;
  final num? ratingGiven;
  final Map<String, dynamic> proofOfDelivery;
  final List<dynamic> supportNotes;

  const SenderDeliveryRecord({
    required this.id,
    required this.senderId,
    required this.requestId,
    required this.parcelDescription,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.createdAt,
    required this.status,
    required this.serviceType,
    required this.assignedDriverName,
    required this.assignedDriverPhone,
    required this.assignedDriverPhotoUrl,
    required this.assignedDriverVehicle,
    required this.pricePaid,
    required this.currency,
    required this.paymentStatus,
    required this.trackingReference,
    required this.irisMatchedItemName,
    required this.parcelWeightKg,
    required this.weightBand,
    required this.recommendedVehicle,
    required this.fragile,
    required this.handlingNotes,
    required this.ratingGiven,
    this.proofOfDelivery = const {},
    this.supportNotes = const [],
  });

  factory SenderDeliveryRecord.fromMap(String id, Map<String, dynamic> data) {
    final pickupDetails =
        Map<String, dynamic>.from(data['pickupDetails'] ?? {});
    final dropoffDetails =
        Map<String, dynamic>.from(data['dropoffDetails'] ?? {});
    final suitability =
        Map<String, dynamic>.from(data['vehicleSuitability'] ?? const {});
    final requestId = '${data['requestId'] ?? id}';
    final price = _parseMoney(data['price'] ??
        data['totalFare'] ??
        data['quote'] ??
        data['amount'] ??
        data['stripeAmount']);
    final rawPaymentStatus = '${data['paymentStatus'] ?? ''}'.trim();
    final assignedRider = data['assignedRider'] is Map
        ? Map<String, dynamic>.from(data['assignedRider'] as Map)
        : const <String, dynamic>{};
    return SenderDeliveryRecord(
      id: id,
      senderId: '${data['senderId'] ?? data['userId'] ?? ''}',
      requestId: requestId,
      parcelDescription:
          '${data['packageDescription'] ?? pickupDetails['moreInformation'] ?? 'Parcel'}',
      pickupAddress:
          '${data['pickupAddress'] ?? pickupDetails['address'] ?? ''}',
      dropoffAddress:
          '${data['dropoffAddress'] ?? dropoffDetails['address'] ?? ''}',
      createdAt: parseDate(data['createdAt']),
      status: '${data['status'] ?? 'requested'}',
      serviceType: '${data['serviceType'] ?? ''}',
      assignedDriverName:
          '${data['riderName'] ?? data['driverName'] ?? data['courierName'] ?? ''}',
      assignedDriverPhone:
          '${data['riderPhone'] ?? data['driverPhone'] ?? data['courierPhone'] ?? ''}',
      assignedDriverPhotoUrl:
          '${assignedRider['photoURL'] ?? data['riderPhotoURL'] ?? data['riderPhotoUrl'] ?? data['driverPhotoUrl'] ?? data['photoURL'] ?? data['photoUrl'] ?? ''}',
      assignedDriverVehicle:
          '${data['vehicleMakeModel'] ?? data['vehicleType'] ?? data['vehicle'] ?? ''}',
      pricePaid: price,
      currency: '${data['currency'] ?? 'GBP'}',
      paymentStatus: rawPaymentStatus.isNotEmpty
          ? rawPaymentStatus
          : _inferPaymentStatus(data, price),
      trackingReference: '${data['code'] ?? requestId}',
      irisMatchedItemName:
          '${data['irisMatchedItemName'] ?? data['normalizedItemName'] ?? ''}',
      parcelWeightKg: _parseMoney(data['finalWeightKg'] ??
          data['finalWeightUsed'] ??
          data['weightKg'] ??
          data['confirmedWeightKg']),
      weightBand:
          '${data['finalWeightBand'] ?? data['weightBand'] ?? data['weightCategory'] ?? ''}',
      recommendedVehicle:
          '${data['irisRecommendedVehicle'] ?? suitability['recommendedVehicle'] ?? data['vehicleType'] ?? data['vehicle'] ?? ''}',
      fragile: data['fragile'] == true || suitability['fragile'] == true,
      handlingNotes:
          '${data['irisImageHandlingNotes'] ?? suitability['handlingNotes'] ?? data['specialHandlingNotes'] ?? ''}',
      ratingGiven: data['riderRating'] ?? data['userRating'],
      proofOfDelivery:
          Map<String, dynamic>.from(data['proofOfDelivery'] ?? const {}),
      supportNotes: data['supportNotes'] as List<dynamic>? ?? const [],
    );
  }

  static String _inferPaymentStatus(Map<String, dynamic> data, double price) {
    final status = '${data['status'] ?? ''}'.toLowerCase();
    if (status.contains('payment_pending') ||
        status.contains('awaiting_payment')) {
      return 'pending';
    }
    if (data['paidByRoth'] == true ||
        data['cardPaymentCompleted'] == true ||
        '${data['stripePaymentId'] ?? data['paymentIntentId'] ?? data['stripeIntentId'] ?? ''}'
            .trim()
            .isNotEmpty ||
        price > 0) {
      return 'paid';
    }
    return 'pending';
  }
}

class SenderProfileSummary {
  final int completedDeliveries;
  final int totalDeliveries;
  final double lifetimeValue;
  final double? averageSenderRating;
  final String loyaltyLevel;

  const SenderProfileSummary({
    required this.completedDeliveries,
    required this.totalDeliveries,
    required this.lifetimeValue,
    required this.averageSenderRating,
    required this.loyaltyLevel,
  });
}

class SenderProfileService {
  static List<SenderDeliveryRecord> ownDeliveries(
    String senderUid,
    Iterable<SenderDeliveryRecord> deliveries,
  ) {
    return deliveries
        .where((delivery) => delivery.senderId == senderUid)
        .toList(growable: false);
  }

  static SenderProfileSummary summarize(
    Iterable<SenderDeliveryRecord> deliveries, {
    Iterable<num> senderRatings = const [],
  }) {
    final records = deliveries.toList(growable: false);
    final completed = records
        .where((record) => record.status.toLowerCase() == 'completed')
        .length;
    final value = records.fold<double>(
      0,
      (total, delivery) => total + delivery.pricePaid,
    );
    final ratings = senderRatings.toList(growable: false);
    final averageRating = ratings.isEmpty
        ? null
        : ratings.fold<double>(0, (total, rating) => total + rating) /
            ratings.length;
    return SenderProfileSummary(
      completedDeliveries: completed,
      totalDeliveries: records.length,
      lifetimeValue: value,
      averageSenderRating: averageRating,
      loyaltyLevel: loyaltyLevel(completed),
    );
  }

  static String loyaltyLevel(int completedDeliveries) {
    if (completedDeliveries >= 25) return 'Priority sender';
    if (completedDeliveries >= 8) return 'Regular sender';
    if (completedDeliveries >= 1) return 'Active sender';
    return 'New sender';
  }

  static String sanitizedPaymentReference(String customerId) {
    if (customerId.length <= 8) return 'Saved payment profile';
    return 'Payment profile ending ${customerId.substring(customerId.length - 4)}';
  }
}

DateTime? parseDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

double _parseMoney(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}
