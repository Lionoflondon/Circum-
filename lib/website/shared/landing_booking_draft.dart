import 'dart:convert';

/// Unverified text only. The booking flow must resolve both addresses and price.
class LandingBookingDraft {
  final String pickup;
  final String destination;
  final DateTime createdAt;

  const LandingBookingDraft(this.pickup, this.destination, this.createdAt);

  String encode() => jsonEncode({
        'pickup': pickup.trim(),
        'destination': destination.trim(),
        'createdAt': createdAt.toUtc().toIso8601String(),
      });

  static LandingBookingDraft? decode(String? raw, DateTime now) {
    if (raw == null || raw.length > 4096) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data['pickup'] is! String ||
          data['destination'] is! String ||
          data['createdAt'] is! String) {
        return null;
      }
      final pickup = (data['pickup'] as String).trim();
      final destination = (data['destination'] as String).trim();
      final createdAt = DateTime.tryParse(data['createdAt'] as String);
      if (pickup.isEmpty ||
          destination.isEmpty ||
          pickup.length > 300 ||
          destination.length > 300 ||
          createdAt == null ||
          now.difference(createdAt) > const Duration(minutes: 30) ||
          createdAt.difference(now) > const Duration(minutes: 1)) {
        return null;
      }
      return LandingBookingDraft(pickup, destination, createdAt);
    } catch (_) {
      return null;
    }
  }
}
