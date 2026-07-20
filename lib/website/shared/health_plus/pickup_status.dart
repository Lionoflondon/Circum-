enum PickupStatus {
  scheduled,
  assigned,
  awaitingPharmacyCollection,
  collected,
  outForDelivery,
  delivered,
  failed,
  cancelled,
}

extension PickupStatusValue on PickupStatus {
  String get value {
    return switch (this) {
      PickupStatus.scheduled => 'scheduled',
      PickupStatus.assigned => 'assigned',
      PickupStatus.awaitingPharmacyCollection => 'awaiting_pharmacy_collection',
      PickupStatus.collected => 'collected',
      PickupStatus.outForDelivery => 'out_for_delivery',
      PickupStatus.delivered => 'delivered',
      PickupStatus.failed => 'failed',
      PickupStatus.cancelled => 'cancelled',
    };
  }

  static PickupStatus fromValue(String value) {
    return PickupStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => PickupStatus.scheduled,
    );
  }
}
