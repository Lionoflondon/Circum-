import 'package:circum/app/delivery/sender_web_booking_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

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

    test('release standard requires end-to-end workflow verification', () {
      final standard = File('docs/rothcross_engineering_release_standard.md')
          .readAsStringSync();

      expect(standard, contains('end-to-end workflows are verified'));
      expect(standard, contains('Booking creation must be atomic'));
      expect(
          standard,
          contains(
              'Payment must never exist without a canonical delivery record'));
      expect(
          standard,
          contains(
              'Rider broadcast only happens after a valid canonical delivery record exists'));
      expect(
          standard, contains('Vanguard/PIN data exists and survives reload'));
    });

    test('Sender Web uses backend quote, payment session and paid delivery',
        () {
      final source = File('lib/web_sender_app.dart').readAsStringSync();
      final quoteIndex = source.indexOf('_createSenderWebBookingQuote(');
      final paymentIndex = source.indexOf('_collectDeliveryPayment(');
      final createIndex = source.indexOf('_createSenderWebPaidDelivery(');

      expect(quoteIndex, isNonNegative);
      expect(paymentIndex, isNonNegative);
      expect(createIndex, isNonNegative);
      expect(quoteIndex, lessThan(paymentIndex));
      expect(paymentIndex, lessThan(createIndex));
      expect(source, contains("httpsCallable('createSenderBookingQuote')"));
      expect(source, contains("httpsCallable('createSenderPaymentSession')"));
      expect(source, contains("httpsCallable('createSenderPaidDelivery')"));
      expect(source, isNot(contains('cloudfunctions.net/createPaymentIntent')));
    });

    test('My Bookings recovers signed-in sender deliveries by UID and email',
        () {
      final source = File('lib/web_sender_app.dart').readAsStringSync();

      expect(source, contains(".where('senderId', isEqualTo: uid)"));
      expect(source, contains(".where('userId', isEqualTo: uid)"));
      expect(source, contains(".where('senderEmailLower', isEqualTo: email)"));
      expect(source, contains(".where('senderEmail', isEqualTo: rawEmail)"));
      expect(source, contains('ownDeliveriesForIdentity'));
    });

    test('incomplete bookings are display-only during history loading', () {
      final source = File('lib/web_sender_app.dart').readAsStringSync();
      final loadStart = source.indexOf('Future<void> _loadSenderDeliveries');
      final loadEnd = source.indexOf(
        'void _openSenderDeliveryTracking',
        loadStart,
      );
      final loader = source.substring(loadStart, loadEnd);

      expect(source,
          isNot(contains('sender_web_booking_recovery_marked_on_load')));
      expect(loader, isNot(contains('doc.reference.set(')));
      expect(source, contains("'broadcastBlocked': true"));
      expect(
        source,
        contains("'broadcastBlockReason': 'missing_canonical_booking_fields'"),
      );
    });

    test('canonical delivery persists recovery aliases for tracking and PINs',
        () {
      final source = File('lib/web_sender_app.dart').readAsStringSync();

      expect(source, contains("'senderEmailLower': senderEmail"));
      expect(source, contains("'authenticatedUserUid': senderId"));
      expect(source, contains("'trackingUrl': '/?app=sender&deliveryId=\$id'"));
      expect(source, contains("'pickupPin': collectionPin"));
      expect(source, contains("'dropoffPin': deliveryPin"));
      expect(source, contains("'pinVerification':"));
    });

    test('tracking resolver never falls back to stale or mock delivery data',
        () {
      final source = File('lib/web_sender_app.dart').readAsStringSync();

      expect(source, contains('Future<String?> _resolveDeliveryId'));
      expect(source, contains('notFound: true'));
      expect(source, contains("collection('deliveryRequests')"));
      expect(source, contains("'paymentReferenceId'"));
      expect(source, isNot(contains('test-route-verification')));
    });

    test('rider queue and accept path block stale archive records', () {
      final source = File('lib/web_sender_app.dart').readAsStringSync();

      expect(source, contains('_isBroadcastBlockedDelivery(job)'));
      expect(
        source,
        contains(
            'This delivery is blocked for recovery and cannot be accepted.'),
      );
      expect(source, contains("'admin_removed_stale'"));
      expect(source, contains("'archived_expired'"));
    });

    test('Admin Archives section keeps stale records searchable', () {
      final source = File('lib/web_sender_app.dart').readAsStringSync();

      expect(source, contains('Delivery Archives'));
      expect(source, contains('_deliveryArchiveRows'));
      expect(source, contains('_deliveryArchiveRow'));
      expect(source, contains('Remove Stale Order'));
      expect(source, contains('admin_removed_stale'));
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
    'trackingUrl': '/?app=sender&deliveryId=CIR-123456',
    'createdAt': DateTime(2026),
    'updatedAt': DateTime(2026),
    'vanguardEnabled': false,
  };
}
