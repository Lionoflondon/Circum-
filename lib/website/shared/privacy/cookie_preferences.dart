import 'dart:convert';

/// Consent is purpose-specific and expires so visitors can review their choice.
class CookiePreferences {
  static const version = 2;
  static const lifetime = Duration(days: 180);
  final bool analytics;
  final bool marketing;
  final DateTime savedAt;

  const CookiePreferences({
    required this.analytics,
    required this.marketing,
    required this.savedAt,
  });

  String encode() => jsonEncode({
        'version': version,
        'analytics': analytics,
        'marketing': marketing,
        'savedAt': savedAt.toUtc().toIso8601String(),
      });

  static CookiePreferences? decode(String? raw, DateTime now) {
    if (raw == null || raw.length > 1024) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map ||
          value['version'] != version ||
          value['analytics'] is! bool ||
          value['marketing'] is! bool ||
          value['savedAt'] is! String) {
        return null;
      }
      final date = DateTime.tryParse(value['savedAt'] as String);
      if (date == null ||
          date.isAfter(now.add(const Duration(minutes: 1))) ||
          now.difference(date) >= lifetime) {
        return null;
      }
      return CookiePreferences(
          analytics: value['analytics'] as bool,
          marketing: value['marketing'] as bool,
          savedAt: date);
    } catch (_) {
      return null;
    }
  }
}
