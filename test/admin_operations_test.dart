import 'package:circum/app/admin/admin_operations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Admin operations', () {
    test('blocks unauthorised users and checks role permissions', () {
      expect(AdminAccessPolicy.hasAnyAdminRole(['customer']), isFalse);
      expect(AdminAccessPolicy.hasAnyAdminRole(['support_agent']), isTrue);
      expect(
        AdminAccessPolicy.can(['support_agent'], AdminPermission.viewCustomers),
        isTrue,
      );
      expect(
        AdminAccessPolicy.can(['support_agent'], AdminPermission.viewFinance),
        isFalse,
      );
      expect(
        AdminAccessPolicy.can(['super_admin'], AdminPermission.viewFinance),
        isTrue,
      );
    });

    test('loads meaningful Firebase-style metrics', () {
      final metrics = AdminMetricSnapshot.fromData(
        now: DateTime(2026, 5, 29, 12),
        deliveries: [
          {
            'requestId': 'CIR-1',
            'status': 'completed',
            'senderId': 'sender-1',
            'price': 12,
          },
          {
            'requestId': 'CIR-2',
            'status': 'requested',
            'senderId': 'sender-1',
            'price': 8,
          },
          {
            'requestId': 'CIR-3',
            'status': 'cancelled',
            'senderId': 'sender-2',
            'price': 9,
          },
        ],
        senders: [
          {'status': 'active'},
          {'status': 'deactivated'},
        ],
        drivers: [
          {'status': 'online', 'verificationStatus': 'verified'},
          {'status': 'offline', 'verificationStatus': 'pending'},
        ],
        payments: [
          {'amount': 12, 'createdAt': DateTime(2026, 5, 29, 9)},
          {'amount': 10, 'createdAt': DateTime(2026, 5, 27, 9)},
        ],
        ratings: [
          {'starRating': 5},
          {'starRating': 4},
        ],
        supportTickets: [
          {'status': 'open', 'type': 'refund_request'},
        ],
        healthPlusPayments: [
          {'amount': 11, 'frequency': 'monthly'},
        ],
      );

      expect(metrics.totalDeliveries, 3);
      expect(metrics.activeDeliveries, 1);
      expect(metrics.completedDeliveries, 1);
      expect(metrics.cancelledDeliveries, 1);
      expect(metrics.totalSenders, 2);
      expect(metrics.activeDrivers, 1);
      expect(metrics.pendingDrivers, 1);
      expect(metrics.revenueToday, 12);
      expect(metrics.revenueThisWeek, 22);
      expect(metrics.averageDriverRating, 4.5);
      expect(metrics.refundRequests, 1);
      expect(metrics.unresolvedSupportIssues, 1);
      expect(metrics.healthPlusRecurringRevenue, 11);
    });

    test('searches customers and drivers', () {
      final customers = [
        {'fullName': 'Jane Smith', 'email': 'jane@circum.app'},
        {'fullName': 'Marcus Driver', 'email': 'driver@circum.app'},
      ];

      expect(adminSearch(customers, 'jane', ['fullName', 'email']).length, 1);
      expect(adminSearch(customers, 'circum', ['email']).length, 2);
    });

    test('duplicates delivery with new id and requested status', () {
      final duplicate = AdminDeliveryTools.duplicateDelivery(
        {
          'requestId': 'CIR-OLD',
          'status': 'completed',
          'price': 15,
          'historyId': 'HIST',
          'proofOfDelivery': 'photo',
        },
        newId: 'CIR-NEW',
        createdAt: DateTime(2026, 5, 29),
      );

      expect(duplicate['requestId'], 'CIR-NEW');
      expect(duplicate['status'], 'requested');
      expect(duplicate['historyId'], isNull);
      expect(duplicate['proofOfDelivery'], isNull);
      expect(duplicate['adminDuplicatedFrom'], 'CIR-OLD');
    });

    test('safe delivery edit patch excludes payment amount changes', () {
      final patch = AdminDeliveryTools.safeDeliveryPatch(
        pickupAddress: 'New pickup',
        parcelNotes: 'Leave at reception',
      );

      expect(patch['pickupAddress'], 'New pickup');
      expect(patch['packageDescription'], 'Leave at reception');
      expect(patch.containsKey('price'), isFalse);
      expect(patch.containsKey('amount'), isFalse);
    });

    test('creates audit log entries', () {
      final audit = AdminAuditEntry(
        adminUserId: 'admin-1',
        actionType: 'delivery_duplicate',
        recordType: 'deliveryRequests',
        recordId: 'CIR-NEW',
        oldValue: const {'requestId': 'CIR-OLD'},
        newValue: const {'requestId': 'CIR-NEW'},
        reason: 'Customer asked to send again',
      ).toJson();

      expect(audit['adminUserId'], 'admin-1');
      expect(audit['actionType'], 'delivery_duplicate');
      expect(audit['reason'], 'Customer asked to send again');
    });
  });
}
