import 'dart:io';

import 'package:circum/app/sender_mobile/sender_notification_routing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses explicit notification destination map', () {
    final destination = parseSenderNotificationDestination({
      'destination': {'route': 'wallet'},
    });

    expect(destination, {'route': 'wallet'});
  });

  test('decodes JSON destination from push data', () {
    final destination = parseSenderNotificationDestination({
      'data': '{"destination":{"route":"tracking","deliveryId":"delivery-1"}}',
    });

    expect(destination['route'], 'tracking');
    expect(destination['deliveryId'], 'delivery-1');
  });

  test('maps legacy chat message payloads to conversation route', () {
    final destination = parseSenderNotificationDestination({
      'type': 'message',
      'data': '{"chatId":"delivery-2"}',
    });

    expect(destination, {'route': 'conversation', 'chatId': 'delivery-2'});
  });

  test('maps payment payloads to wallet route', () {
    final destination = parseSenderNotificationDestination({
      'type': 'payment',
      'data': '{"paymentStatus":"succeeded"}',
    });

    expect(destination, {'route': 'wallet'});
  });

  test(
    'notification centre wallet opens close the centre before selecting Wallet',
    () {
      final source = File(
        'lib/app/sender_mobile/sender_mobile_home.dart',
      ).readAsStringSync();
      final notificationCentre = source.substring(
        source.indexOf('Future<void> _openNotificationCentre'),
      );
      expect(
        notificationCentre,
        contains(
          'onOpenWallet: () {\n                  Navigator.of(context).pop();\n                  _selectTab(3);',
        ),
      );
    },
  );

  test('maps wallet payment payloads to Wallet and preserves transaction id',
      () {
    final destination = parseSenderNotificationDestination({
      'type': 'wallet_payment',
      'transactionId': 'wallet-tx-1',
    });

    expect(destination, {
      'route': 'wallet',
      'transactionId': 'wallet-tx-1',
    });
  });

  test('routes Gift Story ready notification to the referenced Gift', () {
    final destination = parseSenderNotificationDestination({
      'type': 'gift_story_ready',
      'giftId': 'gift-1',
    });

    expect(destination, {'route': 'gift', 'giftId': 'gift-1'});
  });

  test('foreground Gift Story handling uses a normal local notification', () {
    final messaging = File('lib/messaging.dart').readAsStringSync();
    final giftHandler = messaging.substring(
      messaging.indexOf("message.data['type'] == 'gift_story_ready'"),
    );
    expect(giftHandler, contains('notifyUser('));
    expect(giftHandler, isNot(contains('time-sensitive')));
    expect(giftHandler, isNot(contains('critical')));
  });

  test('falls back unknown payloads to Notification Centre', () {
    final destination = parseSenderNotificationDestination({
      'type': 'unknown',
      'payload': 'not-json',
    });

    expect(destination, {'route': 'notifications'});
  });

  test(
    'delivery destinations open an owned Activity detail, never the booking canvas',
    () {
      final source = File(
        'lib/app/sender_mobile/sender_notification_routing.dart',
      ).readAsStringSync();
      expect(source, contains('SenderDeliveryDetailView'));
      expect(source, contains("destination['deliveryId']"));
      expect(
        source,
        isNot(
          contains(
            "case 'tracking':\n      Navigator.of(context).push(\n        MaterialPageRoute<void>(builder: (_) => const SenderBookingCanvas())",
          ),
        ),
      );
    },
  );

  test('Sender support opens the canonical backend conversation surface', () {
    final supportView = File(
      'lib/app/support/view/support.dart',
    ).readAsStringSync();
    final supportBloc = File(
      'lib/app/support/bloc/support_bloc.dart',
    ).readAsStringSync();

    expect(supportView, contains('RideChatPageView'));
    expect(supportView, contains('supportConversation: true'));
    expect(supportView, isNot(contains("import 'chat.dart'")));
    expect(supportView, isNot(contains('const ChatPageView')));
    expect(
      supportBloc,
      contains("httpsCallable('getOrCreateSupportConversation')"),
    );
    expect(supportBloc, isNot(contains('ChatsHelper')));
    expect(supportBloc, isNot(contains('storeChat')));
  });

  test('chat retry reuses one idempotency key after timeout', () {
    final source = File(
      'lib/app/send_package/view/ride_chats.dart',
    ).readAsStringSync();
    expect(source, contains('_pendingMessageIdempotencyKey'));
    expect(source, contains("'idempotencyKey': idempotencyKey"));
    expect(source, contains('Message timed out. Your text is preserved'));
  });

  test('Sender push payload parsing is recoverable and diagnostic', () {
    final messaging = File('lib/messaging.dart').readAsStringSync();

    expect(messaging, contains('_decodeCommunicationPayload'));
    expect(messaging, contains('_logRecoverablePushPayload'));
    expect(messaging, contains('Recoverable Sender push payload discarded'));
    expect(
      messaging,
      isNot(
        contains("Map<String, dynamic> msg = jsonDecode(message.data['data'])"),
      ),
    );
  });
}
