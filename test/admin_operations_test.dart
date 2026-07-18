import 'dart:io';

import 'package:circum/app/admin/admin_operations.dart';
import 'package:circum/app/admin/admin_phase1_shell.dart';
import 'package:circum/app/rider_profiles/driver_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Admin operations', () {
    test('support ticket actions reflect resolved status', () {
      expect(
        AdminSupportTools.actionsForStatus('open'),
        ['Assign', 'Resolve', 'Open Chat'],
      );
      expect(
        AdminSupportTools.actionsForStatus('resolved'),
        ['Reopen', 'View Chat'],
      );
    });

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
      expect(
        AdminAccessPolicy.can(
            ['operations_admin'], AdminPermission.manageHealthPlus),
        isTrue,
      );
      expect(
        AdminAccessPolicy.can(['support_agent'], AdminPermission.viewSupport),
        isTrue,
      );
      expect(
        AdminAccessPolicy.can(
            ['finance_admin'], AdminPermission.approveDrivers),
        isFalse,
      );
      expect(
        AdminAccessPolicy.can(['super_admin'], AdminPermission.manageAdmins),
        isTrue,
      );
      expect(
        AdminAccessPolicy.can(
            ['operations_admin'], AdminPermission.manageAdmins),
        isFalse,
      );
    });

    test('inactive admin records do not grant roles', () {
      expect(
        AdminUserAccess.activeRolesFromRecord({
          'roles': ['support_agent'],
          'status': 'active',
        }),
        ['support_agent'],
      );
      expect(
        AdminUserAccess.activeRolesFromRecord({
          'roles': ['support_agent'],
          'status': 'inactive',
        }),
        isEmpty,
      );
      expect(
        AdminUserAccess.hasInactiveAdminRecord([
          {
            'roles': ['support_agent'],
            'status': 'inactive'
          }
        ]),
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

    test('rider rank defaults and permissions are safe', () {
      expect(RiderRankPolicy.normalize(null), 'agent');
      expect(RiderRankPolicy.normalize('unknown'), 'agent');
      expect(RiderRankPolicy.normalize('Knight'), 'knight');
      expect(RiderRankPolicy.canManage(const ['driver_manager']), isTrue);
      expect(RiderRankPolicy.canManage(const ['support_agent']), isFalse);
      expect(
        RiderDispatchPolicy.explanation('veteran'),
        contains('backbone priority'),
      );
    });

    test('rank update patch requires a reason and records metadata', () {
      final changedAt = DateTime(2026, 6, 14);
      final patch = RiderRankPolicy.updatePatch(
        rank: 'veteran',
        updatedAt: changedAt,
        updatedBy: 'admin-1',
        reason: 'Excellent completion history',
      );
      expect(patch['rank'], 'veteran');
      expect(patch['riderRank'], 'veteran');
      expect(patch['rankUpdatedBy'], 'admin-1');
      expect(patch['rankReason'], 'Excellent completion history');
      expect(
        () => RiderRankPolicy.updatePatch(
          rank: 'warden',
          updatedAt: changedAt,
          updatedBy: 'admin-1',
          reason: '',
        ),
        throwsArgumentError,
      );
    });

    test('creates support ticket status patches for admin queue', () {
      final patch = AdminSupportTools.statusPatch(
        status: 'resolved',
        assignedTo: 'ops@circumuk.com',
        resolutionNote: 'Customer was contacted.',
        updatedAt: DateTime(2026, 5, 31),
      );

      expect(patch['status'], 'resolved');
      expect(patch['assignedTo'], 'ops@circumuk.com');
      expect(patch['resolutionNote'], 'Customer was contacted.');
    });

    test('creates Health+ pickup status patches', () {
      final patch = AdminHealthPlusTools.statusPatch(
        status: 'collected',
        assignedDriverId: 'rider-1',
        updatedAt: DateTime(2026, 5, 31),
      );

      expect(patch['status'], 'collected');
      expect(patch['assignedDriverId'], 'rider-1');
      expect(patch['adminUpdatedAt'], isA<DateTime>());
    });

    test('creates admin user access patches without passwords', () {
      final patch = AdminUserAccess.adminUserPatch(
        email: 'Ops@CircumUK.com',
        role: 'operations_admin',
        status: 'active',
        invitedBy: 'owner@circumuk.com',
        createdAt: DateTime(2026, 5, 31),
        updatedAt: DateTime(2026, 5, 31),
      );

      expect(patch['email'], 'ops@circumuk.com');
      expect(patch['role'], 'operations_admin');
      expect(patch['roles'], ['operations_admin']);
      expect(patch['status'], 'active');
      expect(patch.containsKey('password'), isFalse);
    });

    test('updates admin user access records with one active role', () {
      final patch = AdminUserAccess.adminUserPatch(
        email: 'finance@circumuk.com',
        role: AdminRole.financeAdmin.value,
        status: 'inactive',
        invitedBy: 'owner@circumuk.com',
        updatedAt: DateTime(2026, 5, 31),
        lastLoginAt: DateTime(2026, 5, 30),
      );

      expect(patch['role'], 'finance_admin');
      expect(patch['roles'], ['finance_admin']);
      expect(patch['status'], 'inactive');
      expect(patch['lastLoginAt'], DateTime(2026, 5, 30));
      expect(patch.containsKey('createdAt'), isFalse);
    });

    test('Admin chat composer uses the backend message callable', () {
      final source =
          File('lib/app/admin/admin_phase1_shell.dart').readAsStringSync();
      final sendStart = source.indexOf('Future<void> _sendChatMessage()');
      final sendEnd = source.indexOf('String _authMessage', sendStart);
      expect(sendStart, isNonNegative);
      expect(sendEnd, greaterThan(sendStart));
      final sendSource = source.substring(sendStart, sendEnd);

      expect(sendSource, contains("httpsCallable('sendCircumMessage')"));
      expect(sendSource, isNot(contains(".collection('messages')")));
      expect(sendSource, isNot(contains('.collection("messages")')));
    });

    test('restored Admin shell exposes every required operations module', () {
      expect(
        AdminModule.values.map((module) => module.label),
        containsAll(const [
          'Dashboard',
          'Visitor analytics',
          'Users',
          'Riders',
          'Verification',
          'Deliveries',
          'Support',
          'Finance',
          'Health+',
          'Business',
          'Gifts',
          'Audit',
          'Chat',
          'Settings',
        ]),
      );
      expect(AdminModule.values, contains(AdminModule.discrepancyReview));
    });

    test('Admin data bundle starts empty before live loaders resolve', () {
      final data = AdminDataBundle.empty();

      expect(data.deliveries, isEmpty);
      expect(data.users, isEmpty);
      expect(data.riders, isEmpty);
      expect(data.payments, isEmpty);
      expect(data.supportTickets, isEmpty);
      expect(data.auditLogs, isEmpty);
      expect(data.websiteVisitors, isEmpty);
    });
  });
}
