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
      '{"version":1,"analytics":true,"marketing":true,"savedAt":"2026-10-08"}',
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
  test('restoration keeps timestamp and expires exactly at 180 days', () {
    final choice =
        CookiePreferences(analytics: true, marketing: false, savedAt: now);
    final restored = CookiePreferences.decode(
        choice.encode(), now.add(const Duration(days: 179)))!;
    expect(restored.savedAt, now);
    expect(restored.analytics, isTrue);
    expect(restored.marketing, isFalse);
    expect(
        CookiePreferences.decode(
            choice.encode(), now.add(CookiePreferences.lifetime)),
        isNull);
  });
  test('withdrawal persists both optional categories off after refresh', () {
    final withdrawn =
        CookiePreferences(analytics: false, marketing: false, savedAt: now);
    final restored = CookiePreferences.decode(
        withdrawn.encode(), now.add(const Duration(hours: 1)))!;
    expect(restored.analytics, isFalse);
    expect(restored.marketing, isFalse);
  });
  test(
      'browser expiry checks use safe timer intervals without renewing consent',
      () {
    final choice =
        CookiePreferences(analytics: true, marketing: true, savedAt: now);
    expect(choice.reviewDelay(now), const Duration(days: 1));
    expect(choice.reviewDelay(now.add(const Duration(days: 179, hours: 23))),
        const Duration(hours: 1));
    expect(
        choice.reviewDelay(now.add(const Duration(days: 181))), Duration.zero);
    expect(choice.savedAt, now);
  });
}
