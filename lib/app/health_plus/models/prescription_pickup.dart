import 'pickup_status.dart';

class PrescriptionPickup {
  final String id;
  final String profileId;
  final String? scheduleId;
  final String pharmacyAddress;
  final String deliveryAddress;
  final String notes;
  final PickupStatus status;
  final String? assignedDriverId;
  final DateTime preferredPickupAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PrescriptionPickup({
    required this.id,
    required this.profileId,
    required this.scheduleId,
    required this.pharmacyAddress,
    required this.deliveryAddress,
    required this.notes,
    required this.status,
    required this.assignedDriverId,
    required this.preferredPickupAt,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'scheduleId': scheduleId,
        'pharmacyAddress': pharmacyAddress,
        'deliveryAddress': deliveryAddress,
        'notes': notes,
        'status': status.value,
        'assignedDriverId': assignedDriverId,
        'preferredPickupAt': preferredPickupAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
