import 'package:circum/app/sender_mobile/sender_notification_taxonomy.dart';
import 'package:circum/app/sender_mobile/sender_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 29, 12);

  test('wallet payment is visible in All and Wallet taxonomy', () {
    const wallet = {
      'recipientId': 'sender-1',
      'category': 'wallet',
      'type': 'wallet_payment',
      'destination': {'route': 'wallet'},
      'read': false,
    };

    expect(senderNotificationCategory(wallet), SenderNotificationCategory.wallet);
    expect(senderNotificationCategoryKey(wallet), 'wallet');
    expect(senderNotificationVisible(wallet, now: now, recipientId: 'sender-1'), isTrue);
  });

  test('one wallet notification remains one logical card in All and Wallet', () {
    const notification = CircumNotification(
      id: 'wallet-1',
      title: 'Wallet payment received',
      body: 'Synthetic QA wallet payment.',
      category: 'wallet',
      read: false,
      archived: false,
      destination: {'route': 'wallet'},
    );
    expect(senderNotificationMatchesFilter('All', notification), isTrue);
    expect(senderNotificationMatchesFilter('Wallet', notification), isTrue);
    expect(senderNotificationMatchesFilter('Deliveries', notification), isFalse);
  });

  test('visibility hides archive, suppression, expiry and wrong owner', () {
    const base = {'recipientId': 'sender-1', 'read': true};
    expect(senderNotificationVisible(base, now: now, recipientId: 'sender-1'), isTrue);
    expect(senderNotificationVisible({...base, 'archived': true}, now: now, recipientId: 'sender-1'), isFalse);
    expect(senderNotificationVisible({...base, 'suppressed': true}, now: now, recipientId: 'sender-1'), isFalse);
    expect(senderNotificationVisible({...base, 'expiresAt': Timestamp.fromDate(now)}, now: now, recipientId: 'sender-1'), isFalse);
    expect(senderNotificationVisible(base, now: now, recipientId: 'sender-2'), isFalse);
    expect(
      senderNotificationVisible(
        {...base, 'excludeFromCustomerNotifications': true},
        now: now,
        recipientId: 'sender-1',
      ),
      isFalse,
    );
  });

  test('known families survive aliases and unknown values fall back safely', () {
    expect(senderNotificationCategory({'category': 'payments'}), SenderNotificationCategory.wallet);
    expect(senderNotificationCategory({'type': 'chat_message'}), SenderNotificationCategory.chat);
    expect(senderNotificationCategory({'category': 'unrecognised_future_value'}), SenderNotificationCategory.system);
    expect(senderNotificationCategory({'type': 'gift_story_ready'}), SenderNotificationCategory.gifts);
    expect(senderNotificationCategory({'type': 'business_invoice_paid'}), SenderNotificationCategory.business);
    expect(senderNotificationCategory({'type': 'health_plus_ready'}), SenderNotificationCategory.health);
    expect(
      senderNotificationCategory({
        'data': {
          'category': 'wallet',
          'type': 'wallet_payment',
          'destination': {'route': 'wallet'},
        },
      }),
      SenderNotificationCategory.wallet,
    );
  });
}
