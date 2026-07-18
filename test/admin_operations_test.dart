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
        AdminAccessPolicy.can(['finance_admin'], AdminPermission.manageFinance),
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

    test('derives platform health and alerts from live records', () {
      final health = AdminPlatformHealthSnapshot.fromData(
        deliveries: [
          {
            'requestId': 'active-1',
            'status': 'in_transit',
            'vanguardProtection': true,
          },
          {
            'requestId': 'wait-1',
            'status': 'waiting',
          },
          {
            'requestId': 'iris-1',
            'status': 'awaiting_review',
            'reviewType': 'iris_discrepancy',
          },
          {
            'requestId': 'done-1',
            'status': 'completed',
          },
        ],
        payments: [
          {'id': 'pay-1', 'financeReviewStatus': 'escalated'},
        ],
        supportTickets: [
          {'id': 'ticket-1', 'status': 'open'},
        ],
        healthPlusPickups: [
          {'id': 'health-1', 'status': 'assigned'},
        ],
        businessAccounts: [
          {'id': 'business-1', 'status': 'pending'},
        ],
        giftOrders: [
          {'id': 'gift-1', 'status': 'review'},
        ],
      );

      expect(health.activeJobs, 3);
      expect(health.waitingJobs, 1);
      expect(health.vanguardJobs, 1);
      expect(health.discrepancyReviews, 1);
      expect(health.walletReviewItems, 1);
      expect(health.supportOpen, 1);
      expect(health.status, 'Watch');
      expect(health.alerts.map((alert) => alert.title),
          containsAll(['Support queue', 'Finance review']));
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

    test('Health+ operation patches preserve medical authority fields', () {
      final patch = AdminHealthPlusTools.statusPatch(
        status: 'review_approved',
        updatedBy: 'health@circumuk.com',
        reason: 'Prescription evidence checked.',
        updatedAt: DateTime(2026, 6, 3),
      );

      expect(patch['clinicalReviewStatus'], 'approved');
      expect(patch['adminReason'], 'Prescription evidence checked.');
      expect(patch.containsKey('medication'), isFalse);
      expect(patch.containsKey('prescription'), isFalse);
      expect(patch.containsKey('finalAmount'), isFalse);
    });

    test('account status patches avoid destructive closure or deletion', () {
      final patch = AdminAccountTools.accountStatusPatch(
        status: 'closure_review',
        updatedBy: 'ops@circumuk.com',
        updatedAt: DateTime(2026, 5, 31),
        reason: 'Customer requested closure.',
      );

      expect(patch['accountStatus'], 'closure_review');
      expect(patch['closureReviewStatus'], 'requested');
      expect(patch['adminStatusReason'], 'Customer requested closure.');
      expect(patch.containsKey('deleted'), isFalse);
      expect(patch.containsKey('balance'), isFalse);
    });

    test('business account status patches preserve account identity', () {
      final patch = AdminAccountTools.businessStatusPatch(
        status: 'approved',
        updatedBy: 'ops@circumuk.com',
        updatedAt: DateTime(2026, 5, 31),
      );

      expect(patch['status'], 'approved');
      expect(patch['verificationStatus'], 'approved');
      expect(patch.containsKey('businessId'), isFalse);
      expect(patch.containsKey('ownerId'), isFalse);
    });

    test('Business operation patches preserve billing authority', () {
      final patch = AdminBusinessOperationsTools.operationPatch(
        status: 'invoice_issue_review',
        updatedBy: 'business@circumuk.com',
        updatedAt: DateTime(2026, 6, 3),
        reason: 'Monthly invoice requested.',
      );

      expect(patch['businessOperationStatus'], 'invoice_issue_review');
      expect(patch['invoiceReviewStatus'], 'invoice_issue_review');
      expect(patch.containsKey('amount'), isFalse);
      expect(patch.containsKey('stripeSubscriptionId'), isFalse);
      expect(patch.containsKey('subscriptionPrice'), isFalse);
    });

    test('merge review records require two distinct accounts', () {
      final record = AdminAccountTools.mergeReviewRecord(
        primaryAccountId: 'user-1',
        duplicateAccountId: 'user-2',
        requestedBy: 'ops@circumuk.com',
        createdAt: DateTime(2026, 5, 31),
      );

      expect(record['status'], 'pending_review');
      expect(record['source'], 'circum-admin');
      expect(
        () => AdminAccountTools.mergeReviewRecord(
          primaryAccountId: 'user-1',
          duplicateAccountId: 'user-1',
          requestedBy: 'ops@circumuk.com',
          createdAt: DateTime(2026, 5, 31),
        ),
        throwsArgumentError,
      );
    });

    test('rider operation patches require reasons and avoid wallet changes',
        () {
      final patch = AdminRiderOperationsTools.statusPatch(
        status: 'under_investigation',
        updatedBy: 'ops@circumuk.com',
        updatedAt: DateTime(2026, 6, 1),
        reason: 'Insurance discrepancy.',
      );

      expect(patch['adminOperationStatus'], 'under_investigation');
      expect(patch['driverStatus'], 'under_investigation');
      expect(patch['investigationStatus'], 'open');
      expect(patch.containsKey('walletBalance'), isFalse);
      expect(patch.containsKey('earnings'), isFalse);
      expect(
        () => AdminRiderOperationsTools.statusPatch(
          status: 'suspended',
          updatedBy: 'ops@circumuk.com',
          updatedAt: DateTime(2026, 6, 1),
          reason: '',
        ),
        throwsArgumentError,
      );
    });

    test('delivery operation patches preserve backend lifecycle authority', () {
      final patch = AdminDeliveryOperationsTools.operationPatch(
        status: 'waiting_review',
        updatedBy: 'ops@circumuk.com',
        updatedAt: DateTime(2026, 6, 1),
        reason: 'Rider waiting evidence submitted.',
      );

      expect(patch['adminOperationStatus'], 'waiting_review');
      expect(patch['waitingReviewStatus'], 'open');
      expect(patch.containsKey('status'), isFalse);
      expect(patch.containsKey('deliveryStatus'), isFalse);
      expect(patch.containsKey('finalAmount'), isFalse);
      expect(patch.containsKey('paymentStatus'), isFalse);
    });

    test('IRIS review patches preserve pricing and lifecycle authority', () {
      final patch = AdminIrisOperationsTools.reviewPatch(
        status: 'learning_flagged',
        updatedBy: 'iris@circumuk.com',
        updatedAt: DateTime(2026, 6, 2),
        reason: 'Recurring category mismatch.',
      );

      expect(patch['irisReviewStatus'], 'learning_flagged');
      expect(patch['irisLearningQueueStatus'], 'pending');
      expect(patch.containsKey('status'), isFalse);
      expect(patch.containsKey('deliveryStatus'), isFalse);
      expect(patch.containsKey('finalAmount'), isFalse);
      expect(patch.containsKey('price'), isFalse);
    });

    test('finance workflow patches do not alter payment authority fields', () {
      final patch = AdminFinanceTools.workflowPatch(
        status: 'reconciled',
        updatedBy: 'finance@circumuk.com',
        updatedAt: DateTime(2026, 5, 31),
        note: 'Stripe dashboard checked.',
      );

      expect(patch['financeReviewStatus'], 'reconciled');
      expect(patch['financeReviewedBy'], 'finance@circumuk.com');
      expect(patch['financeEscalated'], isFalse);
      expect(patch['financeNote'], 'Stripe dashboard checked.');
      expect(patch.containsKey('status'), isFalse);
      expect(patch.containsKey('amount'), isFalse);
      expect(patch.containsKey('paymentIntent'), isFalse);
      expect(patch.containsKey('stripePaymentIntentId'), isFalse);
    });

    test('finance operation review patches preserve payment authority', () {
      final patch = AdminFinanceTools.workflowPatch(
        status: 'refund_approved',
        updatedBy: 'finance@circumuk.com',
        updatedAt: DateTime(2026, 6, 2),
        note: 'Eligible goodwill refund.',
      );

      expect(patch['financeReviewStatus'], 'refund_approved');
      expect(patch['refundReviewStatus'], 'refund_approved');
      expect(patch['financeNote'], 'Eligible goodwill refund.');
      expect(patch.containsKey('amount'), isFalse);
      expect(patch.containsKey('status'), isFalse);
      expect(patch.containsKey('paymentIntent'), isFalse);
    });

    test('finance workflow patches reject unsupported statuses', () {
      expect(
        () => AdminFinanceTools.workflowPatch(
          status: 'paid',
          updatedBy: 'finance@circumuk.com',
          updatedAt: DateTime(2026, 5, 31),
        ),
        throwsArgumentError,
      );
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
