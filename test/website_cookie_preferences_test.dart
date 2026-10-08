import 'package:circum/website/shared/privacy/cookie_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 8);
  test('no choice, legacy, malformed and expired records never grant consent',
      () {
    for (final raw in [
      null,
      'accepted',
      'rejected',
      '{}',
      '[]',
      '{"version":2,"analytics":"true","marketing":true,"savedAt":"2026-10-08"}',
      CookiePreferences(
              analytics: true,
              marketing: true,
              savedAt: now.subtract(CookiePreferences.lifetime))
          .encode(),
      CookiePreferences(
              analytics: true,
              marketing: true,
              savedAt: now.add(const Duration(days: 1)))
          .encode(),
    ]) {
      expect(CookiePreferences.decode(raw, now), isNull);
    }
  });
  test('analytics and marketing permissions stay separate, including rejection',
      () {
    for (final analytics in [false, true]) {
      for (final marketing in [false, true]) {
        final decoded = CookiePreferences.decode(
            CookiePreferences(
                    analytics: analytics, marketing: marketing, savedAt: now)
                .encode(),
            now)!;
        expect(decoded.analytics, analytics);
        expect(decoded.marketing, marketing);
      }
    }
  });
}
