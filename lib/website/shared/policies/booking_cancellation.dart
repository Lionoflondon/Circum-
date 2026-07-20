class BookingCancellationPolicy {
  static const allowedStatuses = {
    'pending',
    'awaiting_rider',
    'rider_assigned',
    'accepted',
  };

  static String normalize(String status) =>
      status.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

  static bool canSenderCancel(String status) =>
      allowedStatuses.contains(normalize(status));
}
