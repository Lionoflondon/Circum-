class HealthPlusProfile {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String pharmacyAddress;
  final String deliveryAddress;
  final String notes;
  final bool consentConfirmed;
  final DateTime createdAt;
  final DateTime updatedAt;

  const HealthPlusProfile({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    required this.pharmacyAddress,
    required this.deliveryAddress,
    required this.notes,
    required this.consentConfirmed,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        'phoneNumber': phoneNumber,
        'pharmacyAddress': pharmacyAddress,
        'deliveryAddress': deliveryAddress,
        'notes': notes,
        'consentConfirmed': consentConfirmed,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory HealthPlusProfile.fromJson(Map<String, dynamic> json) {
    return HealthPlusProfile(
      id: json['id'] as String,
      fullName: json['fullName'] as String,
      phoneNumber: json['phoneNumber'] as String,
      pharmacyAddress: json['pharmacyAddress'] as String,
      deliveryAddress: json['deliveryAddress'] as String,
      notes: json['notes'] as String? ?? '',
      consentConfirmed: json['consentConfirmed'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
