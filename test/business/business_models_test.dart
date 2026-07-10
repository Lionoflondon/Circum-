import 'package:circum/app/business/business_journey_context.dart';
import 'package:circum/app/business/business_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Business models', () {
    test('account approval state is backend driven', () {
      final pending = BusinessAccount.fromMap('one', {
        'businessName': 'Lumen Studios Ltd',
        'status': 'pending',
      });
      final approved = BusinessAccount.fromMap('two', {
        'businessName': 'Northstar Ltd',
        'status': 'approved',
      });

      expect(pending.isApproved, isFalse);
      expect(pending.statusLabel, 'Pending Approval');
      expect(approved.isApproved, isTrue);
      expect(approved.statusLabel, 'Verified Business');
    });

    test('delivery segments preserve canonical delivery states', () {
      final active = BusinessDelivery.fromMap('a', {
        'deliveryStatus': 'in_transit',
      });
      final scheduled = BusinessDelivery.fromMap('b', {
        'deliveryStatus': 'scheduled',
      });
      final completed = BusinessDelivery.fromMap('c', {
        'deliveryStatus': 'delivered',
      });

      expect(active.isActive, isTrue);
      expect(scheduled.isScheduled, isTrue);
      expect(completed.isCompleted, isTrue);
    });

    test('address labels never render literal null values', () {
      final delivery = BusinessDelivery.fromMap('a', {
        'pickupAddress': {
          'formattedAddress': null,
          'addressLine1': 'Eldridge Road'
        },
        'dropoffAddress': 'undefined',
      });

      expect(delivery.pickup, 'Eldridge Road');
      expect(delivery.dropoff, isEmpty);
    });

    test('workspace derives operational totals without duplicate calculations',
        () {
      final account = BusinessAccount.fromMap('business', {
        'businessName': 'Lumen',
        'status': 'approved',
        'teamMembers': [
          {'name': 'Jason', 'role': 'owner'},
        ],
      });
      final workspace = BusinessWorkspaceData(
        account: account,
        deliveries: const [],
        invoices: const [
          BusinessInvoice(
            id: 'inv-1',
            number: '001',
            status: 'due',
            total: 100,
            balanceDue: 80,
            rothApplied: 20,
            deliveryCount: 2,
            paymentReference: '',
          ),
          BusinessInvoice(
            id: 'inv-2',
            number: '002',
            status: 'paid',
            total: 50,
            balanceDue: 0,
            rothApplied: 0,
            deliveryCount: 1,
            paymentReference: '',
          ),
        ],
        healthRequests: const [],
        giftRequests: const [],
        wallet: BusinessWalletSummary.empty,
      );

      expect(workspace.outstandingBalance, 80);
    });

    test('journey context preserves Business billing identity', () {
      final account = BusinessAccount.fromMap('business-1', {
        'businessName': 'Rothcross',
        'status': 'approved',
        'billingEmail': 'billing@example.com',
      });
      final context = BusinessJourneyContext.forAccount(
        account,
        BusinessJourneyType.delivery,
      );

      expect(context.businessId, 'business-1');
      expect(context.businessName, 'Rothcross');
      expect(context.billingEmail, 'billing@example.com');
      expect(context.billingSource, 'business_finance');
      expect(context.paymentProfileSource, 'shared_payment_profile');
      expect(context.toMap()['businessMode'], isTrue);
    });
  });
}
