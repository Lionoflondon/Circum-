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

  test('falls back unknown payloads to Notification Centre', () {
    final destination = parseSenderNotificationDestination({
      'type': 'unknown',
      'payload': 'not-json',
    });

    expect(destination, {'route': 'notifications'});
  });
}
