import 'package:circum/app/sender_mobile/sender_profile_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preferences use safe defaults and reject unsupported values', () {
    final preferences = SenderProfilePreferences.fromMap({
      'language': 'fr',
      'timeFormat': 'free-form',
      'notificationPreferences': {
        'deliveryUpdates': false,
        'accountAlerts': true,
        'marketing': true,
      },
    });

    expect(preferences.language, 'en');
    expect(preferences.timeFormat, 'automatic');
    expect(preferences.notifications.deliveryUpdates, isFalse);
    expect(preferences.notifications.accountAlerts, isTrue);
    expect(preferences.notifications.marketing, isTrue);
  });

  test('preferences round-trip preserves supported account settings', () {
    const original = SenderProfilePreferences(
      language: 'device_default',
      timeFormat: '24_hour',
      notifications: SenderNotificationPreferences(
        deliveryUpdates: false,
        accountAlerts: true,
        marketing: true,
      ),
    );

    final restored = SenderProfilePreferences.fromMap(original.toMap());

    expect(restored.language, original.language);
    expect(restored.timeFormat, original.timeFormat);
    expect(restored.notifications.toMap(), original.notifications.toMap());
  });
}
