import 'dart:io';

import 'package:circum/app/sender_mobile/sender_notification_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sender notification streams use server ordering before limits', () {
    final centreSource = File(
      'lib/app/sender_mobile/sender_notifications.dart',
    ).readAsStringSync();
    final homeSource = File(
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ).readAsStringSync();

    for (final source in [centreSource, homeSource]) {
      final recipient = source.indexOf(".where('recipientId', isEqualTo: uid)");
      final order = source.indexOf(".orderBy('createdAt', descending: true)");
      final limit = source.indexOf('.limit(', order);

      expect(recipient, isNonNegative);
      expect(order, greaterThan(recipient));
      expect(limit, greaterThan(order));
    }

    expect(centreSource, isNot(contains('results.sort(')));
    expect(homeSource, isNot(contains('items.sort(')));
    expect(centreSource, contains('senderNotificationVisible'));
    expect(homeSource, contains('senderNotificationVisible'));
    expect(
      centreSource,
      contains('late final Stream<List<CircumNotification>> _notifications'),
    );
    expect(centreSource, contains('stream: _notifications'));
    expect(
      centreSource,
      isNot(contains('stream: _repository.watchNotifications()')),
    );
    expect(centreSource, contains('projectSenderNotification'));
    expect(homeSource, contains('projectSenderNotification'));
  });

  test('canonical wallet payment remains visible and routes to Wallet', () {
    final projection = projectSenderNotification({
      'schemaVersion': 1,
      'recipientId': 'qa-sender',
      'type': 'wallet_payment',
      'category': 'payments',
      'family': 'wallet',
      'product': 'wallet',
      'source': 'wallet',
      'read': true,
      'archived': false,
      'suppressed': false,
      'createdAt': DateTime(2026, 9, 29, 12),
      'expiresAt': DateTime(2026, 9, 29, 13),
      'destination': {'route': 'wallet'},
    }, now: DateTime(2026, 9, 29, 12, 30));

    expect(projection.category, 'wallet');
    expect(projection.route, 'wallet');
    expect(projection.visible, isTrue);
    expect(projection.read, isTrue);
  });

  test(
    'unknown notification types degrade safely and state flags govern visibility',
    () {
      final unknown = projectSenderNotification({
        'type': 'future_type',
        'createdAt': DateTime(2026, 9, 29),
      });
      expect(unknown.category, 'system');
      expect(unknown.route, 'notifications');
      expect(unknown.visible, isTrue);
      expect(
        projectSenderNotification({
          'type': 'wallet_payment',
          'read': true,
          'suppressed': true,
        }).visible,
        isFalse,
      );
    },
  );
}
