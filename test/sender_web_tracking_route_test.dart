import 'package:circum/app/delivery/sender_web_tracking_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sender web tracking route persistence', () {
    test('uses deliveryId from the URL as the route delivery source', () {
      final uri = Uri.parse('https://circumuk.com/?app=sender&deliveryId=abc');

      expect(senderDeliveryRouteIdFromUri(uri), 'abc');
    });

    test('accepts purchaseId and reference as recoverable delivery route ids',
        () {
      expect(
        senderDeliveryRouteIdFromUri(
          Uri.parse('https://circumuk.com/?app=business&purchaseId=pur_123'),
        ),
        'pur_123',
      );
      expect(
        senderDeliveryRouteIdFromUri(
          Uri.parse('https://circumuk.com/?app=profile&reference=CIR-123'),
        ),
        'CIR-123',
      );
    });

    test('ignores empty and literal null delivery ids', () {
      expect(
        senderDeliveryRouteIdFromUri(
          Uri.parse('https://circumuk.com/?app=sender&deliveryId='),
        ),
        isNull,
      );
      expect(
        senderDeliveryRouteIdFromUri(
          Uri.parse('https://circumuk.com/?app=sender&deliveryId=null'),
        ),
        isNull,
      );
    });
  });
}
