import 'dart:io';

import 'package:circum/app/sender_mobile/sender_mobile_home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'home hides archived notifications and orphaned delivery-created alerts',
    () {
      const order = SenderHomeOrder(
        id: 'delivery-1',
        bookingId: 'booking-1',
        title: 'Parcel',
        route: 'A → B',
        status: 'In transit',
        rawStatus: 'in_transit',
      );

      expect(
        senderHomeNotificationIsRelevant(
          const SenderHomeNotification(
            id: 'archived',
            title: 'Delivery created',
            body: '',
            read: false,
            archived: true,
          ),
          const [order],
        ),
        isFalse,
      );
      expect(
        senderHomeNotificationIsRelevant(
          const SenderHomeNotification(
            id: 'orphan',
            title: 'Delivery created',
            body: '',
            read: false,
            type: 'delivery_created',
            bookingId: 'deleted-booking',
          ),
          const [order],
        ),
        isFalse,
      );
      expect(
        senderHomeNotificationIsRelevant(
          const SenderHomeNotification(
            id: 'current',
            title: 'Delivery created',
            body: '',
            read: false,
            type: 'delivery_created',
            bookingId: 'booking-1',
          ),
          const [order],
        ),
        isTrue,
      );
    },
  );

  test('home orders are sorted by update time before the query limit', () {
    final source = File(
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ).readAsStringSync();
    final repositoryClass =
        source.indexOf('class FirebaseSenderHomeRepository');
    final repositoryStart = source.indexOf(
      'Stream<List<SenderHomeOrder>> watchRecentOrders()',
      repositoryClass,
    );
    final notificationsStart = source.indexOf(
      'Stream<List<SenderHomeNotification>> watchNotifications()',
      repositoryStart,
    );
    final query = source.substring(repositoryStart, notificationsStart);

    expect(query.indexOf(".where('senderId', isEqualTo: uid)"), isNonNegative);
    expect(
      query.indexOf(".orderBy('updatedAt', descending: true)"),
      greaterThan(query.indexOf(".where('senderId', isEqualTo: uid)")),
    );
    expect(
      query.indexOf('.limit(20)'),
      greaterThan(query.indexOf(".orderBy('updatedAt', descending: true)")),
    );
    expect(query, contains('return orders.take(3).toList(growable: false)'));
  });

  test('home delivery actions watch and open the selected delivery', () {
    final source = File('lib/app/sender_mobile/sender_mobile_home.dart')
        .readAsStringSync();
    expect(source, contains('WatchActiveDelivery(requestId: id)'));
    expect(source, contains('onTap: () => onOpenDelivery(order.id)'));
  });
}
