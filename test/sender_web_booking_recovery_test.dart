import 'package:circum/app/delivery/sender_web_booking_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SenderWebBookingRecovery', () {
    test('complete paid booking can broadcast to riders', () {
      final booking = _completeBooking();

      expect(SenderWebBookingRecovery.missingCanonicalFields(booking), isEmpty);
      expect(SenderWebBookingRecovery.canBroadcast(booking), isTrue);
      expect(
        SenderWebBookingRecovery.visibleStatus(booking),
        SenderWebBookingRecovery.broadcasting,
      );
    });

    test('missing canonical fields become recoverable instead of live jobs',
        () {
      final booking = _completeBooking()
        ..remove('dropoffAddress')
        ..remove('dropoffDetails');

      expect(
        SenderWebBookingRecovery.missingCanonicalFields(booking),
        contains('drop-off address'),
      );
      expect(SenderWebBookingRecovery.canBroadcast(booking), isFalse);
    });

    test('Vanguard bookings require persisted PIN and verification fields', () {
      final booking = _completeBooking()
        ..['vanguardEnabled'] = true
        ..['vanguardProtection'] = {
          'enabled': true,
          'collectionPin': '123456',
        };

      expect(
        SenderWebBookingRecovery.missingCanonicalFields(booking),
        contains('drop-off PIN'),
      );

      booking['vanguardProtection'] = {
        'enabled': true,
        'collectionPin': '123456',
        'deliveryPin': '654321',
      };
      booking['collectionPinVerified'] = false;
      booking['deliveryPinVerified'] = false;

      expect(SenderWebBookingRecovery.missingCanonicalFields(booking), isEmpty);
    });

    test('awaiting payment bookings are recoverable and not broadcastable', () {
      final booking = _completeBooking()
        ..['paymentStatus'] = 'payment_pending'
        ..addAll(SenderWebBookingRecovery.lifecycleFields(
          status: SenderWebBookingRecovery.awaitingPayment,
          currentStep: 'payment',
        ));

      expect(
        SenderWebBookingRecovery.visibleStatus(booking),
        SenderWebBookingRecovery.awaitingPayment,
      );
      expect(SenderWebBookingRecovery.isRecoverableOrActive(booking), isTrue);
      expect(SenderWebBookingRecovery.canBroadcast(booking), isFalse);
    });

    test('completed and cancelled bookings are terminal', () {
      expect(
        SenderWebBookingRecovery.isTerminal({
          'status': 'delivered',
          'paymentStatus': 'paid',
        }),
        isTrue,
      );
      expect(
        SenderWebBookingRecovery.isTerminal({
          'deliveryStatus': 'cancelled',
          'paymentStatus': 'paid',
        }),
        isTrue,
      );
    });
  });
}

Map<String, dynamic> _completeBooking() {
  return {
    'deliveryId': 'CIR-123456',
    'requestId': 'CIR-123456',
    'senderId': 'sender-1',
    'senderEmail': 'sender@example.com',
    'pickupAddress': '1 Pickup Street, London',
    'dropoffAddress': '2 Dropoff Road, London',
    'pickupDetails': {'address': '1 Pickup Street, London'},
    'dropoffDetails': {'address': '2 Dropoff Road, London'},
    'receiverName': 'Recipient',
    'receiverDetails': {'name': 'Recipient'},
    'packageDescription': 'Documents',
    'irisDeliveryEstimateId': 'CIR-123456',
    'selectedServiceLevel': 'standard',
    'paymentStatus': 'paid',
    'status': 'requested',
    'deliveryStatus': SenderWebBookingRecovery.broadcasting,
    'flowStatus': SenderWebBookingRecovery.broadcasting,
    'createdAt': DateTime(2026),
    'updatedAt': DateTime(2026),
    'vanguardEnabled': false,
  };
}
