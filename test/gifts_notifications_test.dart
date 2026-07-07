import 'package:circum/app/admin/admin_operations.dart';
import 'package:circum/app/gifts/gift_system_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Gifts backend readiness', () {
    test('all four Gifts paths create canonical backend records', () {
      final now = DateTime.utc(2026, 7, 7);
      for (final type in GiftSystemPolicy.giftTypes) {
        final record = GiftSystemPolicy.canonicalRecord(
          giftId: 'gift-$type',
          giftType: type,
          userId: 'sender-1',
          email: 'Sender@Example.com',
          updatedAt: now,
          pathFields: type == GiftSystemPolicy.campaignGiftType ||
                  type == GiftSystemPolicy.anonymousGiftType
              ? const {
                  'campaignStatus': 'waiting_for_match',
                  'matchStatus': 'pending',
                  'revealPolicy': 'anonymous_until_mutual_consent',
                  'linkedGiftId': 'linked-gift-1',
                  'linkedParticipantId': 'participant-1',
                }
              : type == GiftSystemPolicy.sendToMeGiftType
                  ? const {
                      'selfGiftFrequency': 'monthly',
                      'stripeMode': 'subscription',
                      'stripeSubscriptionId': 'sub_123',
                      'subscriptionStatus': 'active',
                      'subscriptionInterval': 'month',
                      'subscriptionIntervalCount': 1,
                      'cancelAtPeriodEnd': false,
                    }
                  : const {},
        );

        for (final field in GiftSystemPolicy.backendFields) {
          expect(record.keys, contains(field), reason: '$type missing $field');
        }
        expect(record['giftType'], type);
        expect(record['email'], 'sender@example.com');
      }
    });

    test('sender resume uses backend lifecycle state, not walkthrough state',
        () {
      expect(
        GiftSystemPolicy.resumeRoute({
          'giftType': 'send_to_someone',
          'flowStatus': 'draft',
          'currentStep': 6,
        }),
        '/sender-mobile/gifts/themes',
      );
      expect(
        GiftSystemPolicy.resumeRoute({
          'giftType': 'send_to_me',
          'paymentStatus': 'paid',
          'flowStatus': 'paid',
        }),
        '/sender-mobile/gifts/status',
      );
      expect(
        GiftSystemPolicy.resumeRoute({
          'giftType': 'campaign',
          'campaignStatus': 'waiting_for_match',
          'paymentStatus': 'paid',
        }),
        '/sender-mobile/gifts/campaign',
      );
      expect(
        GiftSystemPolicy.resumeRoute({
          'giftType': 'anonymous',
          'linkedDeliveryStatus': 'delivered',
          'riderCompletionAccepted': true,
          'deliveryVerificationCompleted': true,
          'deliveryAuditSuccessful': true,
        }),
        '/sender-mobile/gifts/story',
      );
    });
  });

  group('Gifts notifications', () {
    test('every required event creates an in-app notification record', () {
      for (final event in GiftSystemPolicy.notificationEvents) {
        final payload = GiftSystemPolicy.notificationPayload(
          event: event,
          userId: 'sender-1',
          email: 'sender@example.com',
          giftId: 'gift-1',
          giftType: GiftSystemPolicy.sendToSomeoneGiftType,
          title: 'Title',
          body: 'Body',
        );

        expect(payload['notificationId'], isNotNull);
        expect(payload['eventType'], event);
        expect(payload['channel'], 'in_app');
        expect(payload['deliveryStatus'], 'pending');
        expect(payload['giftType'], GiftSystemPolicy.sendToSomeoneGiftType);
      }
    });

    test('notifications fire only when backend status changes', () {
      expect(
        GiftSystemPolicy.statusChangeNotificationPayload(
          previousStatus: 'paid',
          newStatus: 'paid',
          userId: 'sender-1',
          giftId: 'gift-1',
        ),
        isNull,
      );

      final payload = GiftSystemPolicy.statusChangeNotificationPayload(
        previousStatus: 'paid',
        newStatus: 'curating',
        userId: 'sender-1',
        email: 'sender@example.com',
        giftId: 'gift-1',
        giftType: GiftSystemPolicy.anonymousGiftType,
      );

      expect(payload, isNotNull);
      expect(payload!['eventType'], 'curation_started');
      expect(payload['giftType'], GiftSystemPolicy.anonymousGiftType);
    });

    test('delivery and story backend states emit required events', () {
      expect(
        GiftSystemPolicy.statusChangeNotificationPayload(
          previousStatus: 'curating',
          newStatus: 'ready_for_gift_delivery',
          userId: 'sender-1',
          giftId: 'gift-1',
        )!['eventType'],
        'ready_for_gift_delivery',
      );
      expect(
        GiftSystemPolicy.statusChangeNotificationPayload(
          previousStatus: 'in_delivery',
          newStatus: 'delivered',
          userId: 'sender-1',
          giftId: 'gift-1',
        )!['eventType'],
        'gift_delivered',
      );
      expect(
        GiftSystemPolicy.statusChangeNotificationPayload(
          previousStatus: 'story_locked',
          newStatus: 'story_unlocked',
          userId: 'sender-1',
          giftId: 'gift-1',
        )!['eventType'],
        'story_unlocked',
      );
    });
  });

  group('Admin Gifts and Roth readiness', () {
    test('admin actions include email audit metadata', () {
      final patch = AdminGiftsOperations.approveRequestPatch(
        adminUserId: 'admin-1',
        adminEmail: 'Admin@Circum.uk',
        previousStatus: 'paid',
        reason: 'Approved by Gifts Team.',
        actionAt: DateTime.utc(2026, 7, 7),
      );

      expect(patch['adminUserId'], 'admin-1');
      expect(patch['adminEmail'], 'admin@circum.uk');
      expect(patch['actionType'], 'gift_request_approved');
    });

    test('admin can issue Roth to a sender wallet with ledger audit', () {
      final issued = AdminRothOperations.issueRothPatch(
        walletId: 'wallet-1',
        userId: 'sender-1',
        email: 'Sender@Example.com',
        balanceBefore: 25,
        amount: 75,
        adminUserId: 'admin-1',
        adminEmail: 'finance@circum.uk',
        reason: 'Launch goodwill credit.',
        createdAt: DateTime.utc(2026, 7, 7),
      );

      final wallet = issued['wallet'] as Map<String, Object?>;
      final ledger = issued['ledger'] as Map<String, Object?>;
      final audit = issued['audit'] as Map<String, Object?>;

      expect(wallet['walletType'], 'sender');
      expect(wallet['balance'], 100);
      expect(wallet['currencyEquivalent'], 'GBP');
      expect(ledger['type'], 'admin_issue');
      expect(ledger['direction'], 'credit');
      expect(ledger['balanceBefore'], 25);
      expect(ledger['balanceAfter'], 100);
      expect(audit['adminEmail'], 'finance@circum.uk');
    });

    test(
        'story remains locked until delivery rules pass or admin override wins',
        () {
      expect(
        GiftSystemPolicy.storyStatusFrom({
          'linkedDeliveryStatus': 'delivered',
          'riderCompletionAccepted': true,
          'deliveryVerificationCompleted': true,
          'deliveryAuditSuccessful': false,
        }),
        'locked',
      );
      expect(
        GiftSystemPolicy.storyStatusFrom({
          'linkedDeliveryStatus': 'delivered',
          'riderCompletionAccepted': true,
          'deliveryVerificationCompleted': true,
          'deliveryAuditSuccessful': true,
        }),
        'unlocked',
      );
      expect(
        GiftSystemPolicy.storyStatusFrom({
          'linkedDeliveryStatus': 'delivered',
          'riderCompletionAccepted': true,
          'deliveryVerificationCompleted': true,
          'deliveryAuditSuccessful': true,
          'giftStoryOverrideType': 'manual_lock',
          'giftStoryAdminUserId': 'admin-1',
          'giftStoryAdminOverrideReason': 'Dispute review.',
          'giftStoryAdminOverrideAt': DateTime.utc(2026, 7, 7),
          'giftStoryPreviousStatus': 'unlocked',
        }),
        'locked',
      );
    });
  });
}
