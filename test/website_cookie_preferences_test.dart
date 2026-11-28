import 'dart:convert';

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
      '{"version":1,"analytics":true,"savedAt":"2026-10-08"}',
      '[]',
      '{"version":3,"analytics":"true","savedAt":"2026-10-08"}',
      CookiePreferences(
              analytics: true, savedAt: now.subtract(CookiePreferences.lifetime))
          .encode(),
      CookiePreferences(
              analytics: true, savedAt: now.add(const Duration(days: 1)))
          .encode(),
    ]) {
      expect(CookiePreferences.decode(raw, now), isNull);
    }
  });
  test('legacy marketing consent is ignored while analytics choice is kept', () {
    final legacy = CookiePreferences.decode(
      '{"version":2,"analytics":true,"marketing":true,"savedAt":"${now.toIso8601String()}"}',
      now,
    )!;
    expect(legacy.analytics, isTrue);
    expect(jsonDecode(legacy.encode()), {
      'version': CookiePreferences.version,
      'analytics': true,
      'savedAt': now.toIso8601String(),
    });
  });
  test('restoration keeps timestamp and expires exactly at 180 days', () {
    final choice = CookiePreferences(analytics: true, savedAt: now);
    final restored = CookiePreferences.decode(
        choice.encode(), now.add(const Duration(days: 179)))!;
    expect(restored.savedAt, now);
    expect(restored.analytics, isTrue);
    expect(
        CookiePreferences.decode(
            choice.encode(), now.add(CookiePreferences.lifetime)),
        isNull);
  });
  test('analytics withdrawal persists after refresh', () {
    final withdrawn = CookiePreferences(analytics: false, savedAt: now);
    final restored = CookiePreferences.decode(
        withdrawn.encode(), now.add(const Duration(hours: 1)))!;
    expect(restored.analytics, isFalse);
  });
  test(
      'browser expiry checks use safe timer intervals without renewing consent',
      () {
    final choice = CookiePreferences(analytics: true, savedAt: now);
    expect(choice.reviewDelay(now), const Duration(days: 1));
    expect(choice.reviewDelay(now.add(const Duration(days: 179, hours: 23))),
        const Duration(hours: 1));
    expect(
        choice.reviewDelay(now.add(const Duration(days: 181))), Duration.zero);
    expect(choice.savedAt, now);
  });
}
