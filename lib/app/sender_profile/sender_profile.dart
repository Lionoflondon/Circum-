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

class SavedSenderAddress {
  final String label;
  final String address;
  final String addressType;
  final String notes;

  const SavedSenderAddress({
    required this.label,
    required this.address,
    this.addressType = 'pickup',
    this.notes = '',
  });

  factory SavedSenderAddress.fromMap(Map<String, dynamic> data) {
    return SavedSenderAddress(
      label: '${data['label'] ?? 'Saved address'}',
      address: '${data['address'] ?? ''}',
      addressType:
          '${data['addressType'] ?? data['type'] ?? data['usage'] ?? 'pickup'}',
      notes: '${data['notes'] ?? data['moreInformation'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'address': address,
        'addressType': addressType,
        if (notes.trim().isNotEmpty) 'notes': notes,
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
  final String assignedDriverName;
  final double pricePaid;
  final String currency;
  final String paymentStatus;
  final String trackingReference;
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
    required this.assignedDriverName,
    required this.pricePaid,
    required this.currency,
    required this.paymentStatus,
    required this.trackingReference,
    required this.ratingGiven,
    this.proofOfDelivery = const {},
    this.supportNotes = const [],
  });

  factory SenderDeliveryRecord.fromMap(String id, Map<String, dynamic> data) {
    final pickupDetails =
        Map<String, dynamic>.from(data['pickupDetails'] ?? {});
    final dropoffDetails =
        Map<String, dynamic>.from(data['dropoffDetails'] ?? {});
    final requestId = '${data['requestId'] ?? id}';
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
      assignedDriverName:
          '${data['riderName'] ?? data['driverName'] ?? data['courierName'] ?? ''}',
      pricePaid: _parseMoney(data['price'] ?? data['quote'] ?? data['amount']),
      currency: '${data['currency'] ?? 'GBP'}',
      paymentStatus: '${data['paymentStatus'] ?? 'pending'}',
      trackingReference: '${data['code'] ?? requestId}',
      ratingGiven: data['riderRating'] ?? data['userRating'],
      proofOfDelivery:
          Map<String, dynamic>.from(data['proofOfDelivery'] ?? const {}),
      supportNotes: data['supportNotes'] as List<dynamic>? ?? const [],
    );
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
