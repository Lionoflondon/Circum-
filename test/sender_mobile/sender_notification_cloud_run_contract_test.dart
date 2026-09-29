import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender notification state has no canonical Gen1 caller', () {
    final sources = [
      File(
        'lib/app/sender_mobile/sender_notifications.dart',
      ).readAsStringSync(),
      File('lib/app/sender_mobile/sender_mobile_home.dart').readAsStringSync(),
      File('lib/website/shared/circum_website_app.dart').readAsStringSync(),
    ];
    for (final source in sources) {
      expect(
        source,
        isNot(contains("httpsCallable('updateSenderNotificationState')")),
      );
    }
  });

  test('Sender Home and Notification Centre share the visible predicate', () {
    final centre = File(
      'lib/app/sender_mobile/sender_notifications.dart',
    ).readAsStringSync();
    final home = File(
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ).readAsStringSync();
    expect(centre, contains('senderNotificationVisible'));
    expect(home, contains('senderNotificationVisible'));
    expect(centre, contains('updateSenderNotificationStateViaCloudRun'));
    expect(home, contains('updateSenderNotificationStateViaCloudRun'));
  });

  test(
    'Sender notification open remains bounded and never opens booking canvas',
    () {
      final centre = File(
        'lib/app/sender_mobile/sender_notifications.dart',
      ).readAsStringSync();
      final routing = File(
        'lib/app/sender_mobile/sender_notification_routing.dart',
      ).readAsStringSync();
      expect(centre, contains('Duration(seconds: 8)'));
      expect(centre, contains('could not be opened'));
      expect(routing, contains('SenderDeliveryDetailView'));
      expect(routing, isNot(contains('SenderBookingCanvas')));
    },
  );
}
