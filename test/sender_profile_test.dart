import 'package:circum/app/sender_profile/sender_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sender profile', () {
    test('reads permanent Legend recognition fields', () {
      final profile = SenderProfile.fromMap('legend-1', {
        'fullName': 'Ayo Jason',
        'isLegend': true,
        'legendNumber': 42,
        'legendAwardedAt': DateTime(2026, 6, 14),
      });

      expect(profile.isLegend, isTrue);
      expect(profile.legendNumber, 42);
      expect(profile.legendAwardedAt, DateTime(2026, 6, 14));
    });

    test('prefers canonical nested Legend recognition fields', () {
      final profile = SenderProfile.fromMap('legend-2', {
        'fullName': 'Ayo Jason',
        'isLegend': false,
        'legendNumber': 99,
        'recognitions': {
          'legend': {
            'awarded': true,
            'number': 7,
            'awardedAt': DateTime(2026, 7, 11),
          },
        },
      });

      expect(profile.isLegend, isTrue);
      expect(profile.legendNumber, 7);
      expect(profile.legendAwardedAt, DateTime(2026, 7, 11));
    });

    test('parses the shared mobile users document shape', () {
      final profile = SenderProfile.fromMap('sender-1', {
        'fullname': 'Jane Smith',
        'email': 'jane@circum.app',
        'phoneNumber': '+44 7700 900123',
        'image': 'https://example.com/photo.jpg',
        'customerId': 'cus_test_123456',
      });

      expect(profile.fullName, 'Jane Smith');
      expect(profile.email, 'jane@circum.app');
      expect(profile.phoneNumber, '+44 7700 900123');
      expect(profile.paymentCustomerReference, 'Payment profile ending 3456');
    });

    test('only returns deliveries belonging to the signed-in sender', () {
      final deliveries = [
        SenderDeliveryRecord.fromMap('CIR-1', {
          'senderId': 'sender-1',
          'requestId': 'CIR-1',
          'status': 'completed',
          'price': 12,
        }),
        SenderDeliveryRecord.fromMap('CIR-2', {
          'userId': 'sender-1',
          'requestId': 'CIR-2',
          'status': 'requested',
          'price': 8,
        }),
        SenderDeliveryRecord.fromMap('CIR-3', {
          'senderId': 'other-user',
          'requestId': 'CIR-3',
          'status': 'completed',
          'price': 10,
        }),
      ];

      final own = SenderProfileService.ownDeliveries('sender-1', deliveries);

      expect(own.length, 2);
      expect(own.map((delivery) => delivery.requestId), contains('CIR-1'));
      expect(own.map((delivery) => delivery.requestId), contains('CIR-2'));
    });

    test('recovers deliveries belonging to the signed-in sender email', () {
      final deliveries = [
        SenderDeliveryRecord.fromMap('CIR-EMAIL', {
          'senderEmail': 'sender@example.com',
          'requestId': 'CIR-EMAIL',
          'status': 'requested',
          'price': 33.70,
        }),
        SenderDeliveryRecord.fromMap('CIR-OTHER', {
          'senderEmail': 'other@example.com',
          'requestId': 'CIR-OTHER',
          'status': 'requested',
          'price': 5,
        }),
      ];

      final own = SenderProfileService.ownDeliveriesForIdentity(
        'sender-1',
        'sender@example.com',
        deliveries,
      );

      expect(own.map((delivery) => delivery.requestId), ['CIR-EMAIL']);
    });

    test('reads assigned rider photo snapshot for sender history', () {
      final delivery = SenderDeliveryRecord.fromMap('CIR-1', {
        'senderId': 'sender-1',
        'requestId': 'CIR-1',
        'status': 'accepted',
        'assignedRider': {
          'name': 'Ayo Rider',
          'photoURL': 'https://example.com/rider.jpg',
        },
        'riderName': 'Ayo Rider',
      });

      expect(delivery.assignedDriverName, 'Ayo Rider');
      expect(delivery.assignedDriverPhotoUrl, 'https://example.com/rider.jpg');
    });

    test('falls back to legacy rider photo fields for older deliveries', () {
      final delivery = SenderDeliveryRecord.fromMap('CIR-OLD', {
        'senderId': 'sender-1',
        'requestId': 'CIR-OLD',
        'status': 'completed',
        'driverName': 'Legacy Rider',
        'driverPhotoUrl': 'https://example.com/legacy-rider.jpg',
      });

      expect(delivery.assignedDriverName, 'Legacy Rider');
      expect(
        delivery.assignedDriverPhotoUrl,
        'https://example.com/legacy-rider.jpg',
      );
    });

    test('summarises completed deliveries, value, and loyalty', () {
      final summary = SenderProfileService.summarize([
        SenderDeliveryRecord.fromMap('CIR-1', {
          'senderId': 'sender-1',
          'status': 'completed',
          'price': 11,
        }),
        SenderDeliveryRecord.fromMap('CIR-2', {
          'senderId': 'sender-1',
          'status': 'requested',
          'price': 9,
        }),
      ], senderRatings: const [
        5,
        4,
      ]);

      expect(summary.totalDeliveries, 2);
      expect(summary.completedDeliveries, 1);
      expect(summary.lifetimeValue, 20);
      expect(summary.averageSenderRating, 4.5);
      expect(summary.loyaltyLevel, 'Active sender');
    });

    test('keeps profile update patch away from sensitive payment details', () {
      final patch = SenderProfile(
        id: 'sender-1',
        fullName: 'Jane',
        email: 'jane@circum.app',
        phoneNumber: '+44',
        photoUrl: '',
        verificationStatus: 'verified',
        createdAt: null,
      ).safeUpdatePatch(
        fullName: 'Jane Smith',
        phoneNumber: '+44 7700 900123',
        savedAddresses: const [
          SavedSenderAddress(
            label: 'Home',
            address: '10 Park Drive, London, E14 9GG, United Kingdom',
            addressType: 'pickup',
          ),
        ],
        communicationPreferences: const {'sms': true},
      );

      expect(patch['fullName'], 'Jane Smith');
      expect(patch['savedAddresses'], hasLength(1));
      expect(patch['savedAddresses'].first['addressType'], 'pickup');
      expect(patch['savedAddresses'].first['addressData'],
          isA<Map<String, dynamic>>());
      expect(
        patch['savedAddresses'].first['addressData']['addressLine1'],
        '10 Park Drive',
      );
      expect(
          patch['savedAddresses'].first['addressData']['postcode'], 'E14 9GG');
      expect(patch.containsKey('customerId'), isFalse);
      expect(patch.containsKey('cardNumber'), isFalse);
    });

    test('handles new sender empty states', () {
      final summary = SenderProfileService.summarize(const []);

      expect(summary.totalDeliveries, 0);
      expect(summary.completedDeliveries, 0);
      expect(summary.lifetimeValue, 0);
      expect(summary.loyaltyLevel, 'New sender');
    });

    test('maps sender trust points to tiers and next threshold', () {
      expect(SenderTrustPolicy.tierForPoints(0), 'new_sender');
      expect(SenderTrustPolicy.tierForPoints(25), 'active_sender');
      expect(SenderTrustPolicy.tierForPoints(100), 'regular_sender');
      expect(SenderTrustPolicy.tierForPoints(300), 'priority_sender');
      expect(SenderTrustPolicy.tierForPoints(750), 'platinum_sender');
      expect(SenderTrustPolicy.pointsForNextTier(512), 238);
      expect(SenderTrustPolicy.label('priority_sender'), 'Priority Sender');
    });

    test('parses sender trust fields separately from Legend recognition', () {
      final profile = SenderProfile.fromMap('sender-1', {
        'senderTrustPoints': 512,
        'senderTier': 'priority_sender',
        'senderTrustFrozen': true,
        'isLegend': true,
        'legendNumber': 284,
      });

      expect(profile.trustPoints, 512);
      expect(profile.senderTier, 'priority_sender');
      expect(profile.senderTrustFrozen, isTrue);
      expect(profile.isLegend, isTrue);
      expect(profile.legendNumber, 284);
    });
  });
}
