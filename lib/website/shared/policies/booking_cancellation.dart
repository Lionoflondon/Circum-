class BookingCancellationPolicy {
  static const allowedStatuses = {
    'requested',
    'pending',
    'unmatched',
    'finding_rider',
    'broadcasting',
    'available',
    'awaiting_rider',
    'rider_assigned',
    'accepted',
    'navigating_to_pickup',
    'en_route_to_pickup',
    'arrived_at_pickup',
    'waiting_for_collection',
    'waiting',
  };

  static String normalize(String status) =>
      status.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

  static bool canSenderCancel(String status) =>
      allowedStatuses.contains(normalize(status));
}
