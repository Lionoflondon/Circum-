import 'dart:io';

import 'package:circum/app/admin/admin_operations.dart';
import 'package:circum/app/admin/admin_phase1_shell.dart';
import 'package:circum/app/rider_profiles/driver_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Admin operations', () {
    test('Rider Application Centre records are connected to Admin', () {
      final adminShell =
          File('lib/app/admin/admin_phase1_shell.dart').readAsStringSync();

      expect(adminShell, contains("collection('riderApplications')"));
      expect(adminShell, contains("collection('riderDocuments')"));
      expect(adminShell, contains("collection('riderOnboardingEvents')"));
      expect(adminShell, contains('riderApplications'));
      expect(adminShell, contains('riderOnboardingEvents'));
      expect(adminShell, contains('Rider application review'));
      expect(adminShell, contains('Application Centre'));
      expect(adminShell, contains('Rider onboarding events'));
      expect(adminShell, contains('_sectionStatusSummary'));
    });

    test('support ticket actions reflect resolved status', () {
      expect(AdminSupportTools.actionsForStatus('open'), [
        'Assign',
        'Escalate',
        'Request Information',
        'Resolve',
        'Open Chat',
      ]);
      expect(AdminSupportTools.actionsForStatus('resolved'), [
        'Reopen',
        'View Chat',
      ]);
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
        AdminAccessPolicy.can([
          'operations_admin',
        ], AdminPermission.manageHealthPlus),
        isTrue,
      );
      expect(
        AdminAccessPolicy.can(['support_agent'], AdminPermission.viewSupport),
        isTrue,
      );
      expect(
        AdminAccessPolicy.can([
          'finance_admin',
        ], AdminPermission.approveDrivers),
        isFalse,
      );
      expect(
        AdminAccessPolicy.can(['super_admin'], AdminPermission.manageAdmins),
        isTrue,
      );
      expect(
        AdminAccessPolicy.can([
          'operations_admin',
        ], AdminPermission.manageAdmins),
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
            'status': 'inactive',
          },
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
          {'requestId': 'wait-1', 'status': 'waiting'},
          {
            'requestId': 'iris-1',
            'status': 'awaiting_review',
            'reviewType': 'iris_discrepancy',
          },
          {'requestId': 'done-1', 'status': 'completed'},
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
      expect(
        health.alerts.map((alert) => alert.title),
        containsAll(['Support queue', 'Finance review']),
      );
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
      expect(patch['approvalStatus'], 'approved');
      expect(patch['businessStatus'], 'approved');
      expect(patch['verificationStatus'], 'approved');
      expect(patch['isApproved'], isTrue);
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

    test(
      'rider operation patches require reasons and avoid wallet changes',
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
      },
    );

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

    test('Vanguard custody review patches remain Admin metadata only', () {
      final patch = AdminDeliveryOperationsTools.operationPatch(
        status: 'vanguard_custody_escalated',
        updatedBy: 'ops@circumuk.com',
        updatedAt: DateTime(2026, 6, 1),
        reason: 'Collection evidence is incomplete.',
      );

      expect(patch['adminOperationStatus'], 'vanguard_custody_escalated');
      expect(patch['vanguardCustodyReviewStatus'], 'escalated');
      expect(patch.containsKey('status'), isFalse);
      expect(patch.containsKey('deliveryStatus'), isFalse);
      expect(patch.containsKey('assignedRiderId'), isFalse);
      expect(patch.containsKey('price'), isFalse);
      expect(patch.containsKey('trustScore'), isFalse);
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

    test('IRIS evidence and learning actions remain review metadata only', () {
      final evidencePatch = AdminIrisOperationsTools.reviewPatch(
        status: 'evidence_approved',
        updatedBy: 'iris@circumuk.com',
        updatedAt: DateTime(2026, 6, 4),
        reason: 'Photo evidence is sufficient.',
      );
      final promotedPatch = AdminIrisOperationsTools.reviewPatch(
        status: 'learning_promoted',
        updatedBy: 'iris@circumuk.com',
        updatedAt: DateTime(2026, 6, 4),
        reason: 'Consistent verified object profile.',
      );

      expect(evidencePatch['evidenceReviewStatus'], 'approved');
      expect(promotedPatch['irisLearningQueueStatus'], 'promoted');
      expect(evidencePatch.containsKey('finalAmount'), isFalse);
      expect(promotedPatch.containsKey('deliveryStatus'), isFalse);
      expect(promotedPatch.containsKey('canonicalWeight'), isFalse);
    });

    test('Gift workflow actions remain Admin metadata only', () {
      final patch = AdminGiftTools.workflowPatch(
        status: 'information_requested',
        updatedBy: 'gifts@circumuk.com',
        updatedAt: DateTime(2026, 6, 5),
        reason: 'Need merchant confirmation.',
      );

      expect(patch['giftAdminStatus'], 'information_requested');
      expect(patch['informationRequestStatus'], 'requested');
      expect(patch['giftReviewReason'], 'Need merchant confirmation.');
      expect(patch.containsKey('price'), isFalse);
      expect(patch.containsKey('paymentStatus'), isFalse);
      expect(patch.containsKey('matchedGift'), isFalse);
    });

    test('Support workflow actions require supported statuses', () {
      final patch = AdminSupportTools.statusPatch(
        status: 'escalated',
        assignedTo: 'support@circumuk.com',
        reason: 'Urgent customer issue.',
        updatedAt: DateTime(2026, 6, 5),
      );

      expect(patch['status'], 'escalated');
      expect(patch['supportWorkflowStatus'], 'escalated');
      expect(patch['assignedTo'], 'support@circumuk.com');
      expect(patch['adminReviewReason'], 'Urgent customer issue.');
      expect(
        () => AdminSupportTools.statusPatch(
          status: 'delete_payment',
          updatedAt: DateTime(2026, 6, 5),
        ),
        throwsArgumentError,
      );
    });

    test('Platform operation patches preserve backend authority', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();
      final backend = File(
        'server/functions/admin-operations-authority.js',
      ).readAsStringSync();
      final patch = AdminPlatformTools.operationPatch(
        status: 'maintenance_enabled',
        updatedBy: 'platform@circumuk.com',
        updatedAt: DateTime(2026, 6, 6),
        reason: 'Historical maintenance control confirmed.',
      );

      expect(patch['adminOperationStatus'], 'maintenance_enabled');
      expect(patch['maintenanceMode'], isTrue);
      expect(patch['adminReason'], 'Historical maintenance control confirmed.');
      expect(patch.containsKey('firebaseProject'), isFalse);
      expect(patch.containsKey('hostingTarget'), isFalse);
      expect(patch.containsKey('apiKey'), isFalse);
      expect(source, contains("httpsCallable('adminUpdatePlatformRecord')"));
      expect(backend, contains('PLATFORM_OPERATION_COLLECTIONS'));
      expect(backend, contains('platform_operation_\${status}'));
      expect(
        () => AdminPlatformTools.operationPatch(
          status: 'deploy_all_products',
          updatedBy: 'platform@circumuk.com',
          updatedAt: DateTime(2026, 6, 6),
          reason: 'Nope.',
        ),
        throwsArgumentError,
      );
    });

    test('ratings and tips policy restores historical filters', () {
      final records = [
        AdminRatingTipRecord.fromBackend(
          ratingId: 'rating-1',
          rating: {
            'deliveryId': 'CIR-1',
            'riderId': 'rider-1',
            'senderId': 'sender-1',
            'starRating': 5,
            'reportStatus': 'clear',
          },
          tip: {'amount': 4.5, 'paymentMethod': 'card'},
        ),
        AdminRatingTipRecord.fromBackend(
          ratingId: 'rating-2',
          rating: {
            'deliveryId': 'CIR-2',
            'riderId': 'rider-2',
            'senderId': 'sender-2',
            'starRating': 1,
            'reportStatus': 'reported',
          },
        ),
      ];

      expect(
        AdminRatingsTipsPolicy.filter(
          records,
          filter: AdminRatingTipFilter.tipped,
        ),
        hasLength(1),
      );
      expect(
        AdminRatingsTipsPolicy.filter(
          records,
          filter: AdminRatingTipFilter.reported,
        ),
        hasLength(1),
      );
      expect(
        AdminRatingsTipsPolicy.moderationRequest(
          ratingId: 'rating-2',
          action: 'investigate',
          reason: 'Reported by Sender.',
        ),
        containsPair('action', 'investigate'),
      );
    });

    test('Roth admin issue patch preserves ledger and audit authority', () {
      final patch = AdminRothOperations.issueRothPatch(
        walletId: 'wallet-1',
        userId: 'user-1',
        email: 'User@CircumUk.com',
        balanceBefore: 10,
        amount: 5,
        adminUserId: 'admin-1',
        adminEmail: 'Admin@CircumUk.com',
        reason: 'Compensation approved.',
        createdAt: DateTime(2026, 6, 7),
      );

      expect((patch['wallet'] as Map)['balance'], 15);
      expect((patch['ledger'] as Map)['type'], 'admin_issue');
      expect((patch['audit'] as Map)['adminEmail'], 'admin@circumuk.com');
      expect(patch.containsKey('stripePaymentIntentId'), isFalse);
      expect(
        () => AdminRothOperations.issueRothPatch(
          walletId: 'wallet-1',
          userId: 'user-1',
          email: 'user@circumuk.com',
          balanceBefore: 10,
          amount: 0,
          adminUserId: 'admin-1',
          adminEmail: 'admin@circumuk.com',
          reason: 'Invalid.',
          createdAt: DateTime(2026, 6, 7),
        ),
        throwsArgumentError,
      );
    });

    test('Admin finance UI restores historical backend finance actions', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();

      expect(source, contains("httpsCallable('issueRothToWallets')"));
      expect(source, contains("httpsCallable('setWalletFrozen')"));
      expect(source, contains("httpsCallable('createRiderTransferOrPayout')"));
      expect(source, contains("httpsCallable('adminReviewRiderWithdrawal')"));
      expect(source, isNot(contains('stripeSecretKey')));
      expect(source, isNot(contains('sk_live_')));
    });

    test('Admin payout rejection stays behind backend finance authority', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf(
        'Future<void> _processPayoutRequestFromAdmin',
      );
      final methodEnd = source.indexOf('Future<void> _moderateRating');
      expect(methodStart, isNonNegative);
      expect(methodEnd, greaterThan(methodStart));
      final method = source.substring(methodStart, methodEnd);

      expect(method, contains("httpsCallable('adminReviewRiderWithdrawal')"));
      expect(method, contains("httpsCallable('createRiderTransferOrPayout')"));
      expect(method, isNot(contains("collection('payoutRequests').doc")));
      expect(method, isNot(contains("'status': 'rejected'")));
    });

    test(
      'Admin restores historical Rider Health Plus and Gift Admin parity',
      () {
        final source = File(
          'lib/app/admin/admin_phase1_shell.dart',
        ).readAsStringSync();

        expect(source, contains("httpsCallable('adminReviewRider')"));
        expect(source, contains("httpsCallable('syncStripeConnectStatus')"));
        expect(
          source,
          contains("httpsCallable('resetRiderTestStripeAccount')"),
        );
        expect(source, contains("httpsCallable('adminRecordRiderEvent')"));
        expect(source, contains("collection('recurringPickupSchedules')"));
        expect(source, contains("collection('healthPlusCustodyArchive')"));
        expect(source, contains("collection('giftRequests')"));
        expect(source, contains("collection('giftBrands')"));
        expect(source, contains("collection('giftCampaignParticipants')"));
        expect(source, contains("httpsCallable('retryGiftStoryAutomation')"));
        expect(source, contains("httpsCallable('manageGiftStoryAccess')"));
      },
    );

    test(
      'Admin Rider authority actions do not write Rider records directly',
      () {
        final source = File(
          'lib/app/admin/admin_phase1_shell.dart',
        ).readAsStringSync();
        final methodStart = source.indexOf('Future<void> _setRiderStatus');
        final methodEnd = source.indexOf('Future<void> _syncRiderStripeStatus');
        expect(methodStart, isNonNegative);
        expect(methodEnd, greaterThan(methodStart));
        final statusMethod = source.substring(methodStart, methodEnd);

        expect(source, contains("httpsCallable('adminReviewRider')"));
        expect(statusMethod, contains('_callRiderAuthority'));
        expect(statusMethod, isNot(contains("collection('riderProfiles')")));
        expect(statusMethod, isNot(contains("collection('riders')")));

        final documentStart = source.indexOf(
          'Future<void> _reviewRiderDocument',
        );
        final documentEnd = source.indexOf(
          'Future<void> _removeRiderProfilePhoto',
        );
        expect(documentStart, isNonNegative);
        expect(documentEnd, greaterThan(documentStart));
        final documentMethod = source.substring(documentStart, documentEnd);
        expect(documentMethod, contains('_callRiderAuthority'));
        expect(documentMethod, isNot(contains("collection('riderDocuments')")));

        final photoStart = source.indexOf(
          'Future<void> _removeRiderProfilePhoto',
        );
        final photoEnd = source.indexOf('Future<void> _writeRiderAdminEvent');
        expect(photoStart, isNonNegative);
        expect(photoEnd, greaterThan(photoStart));
        final photoMethod = source.substring(photoStart, photoEnd);
        expect(photoMethod, contains('_callRiderAuthority'));
        expect(photoMethod, isNot(contains('FirebaseStorage.instance')));
      },
    );

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
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();
      final sendStart = source.indexOf('Future<void> _sendChatMessage()');
      final sendEnd = source.indexOf('void _selectChat', sendStart);
      expect(sendStart, isNonNegative);
      expect(sendEnd, greaterThan(sendStart));
      final sendSource = source.substring(sendStart, sendEnd);

      expect(sendSource, contains("httpsCallable('sendCircumMessage')"));
      expect(sendSource, isNot(contains(".collection('messages')")));
      expect(sendSource, isNot(contains('.collection("messages")')));
    });

    test('Admin chat history shows sender names instead of raw ids', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();
      final panelStart = source.indexOf('class _ChatMessageHistoryPanel');
      final panelEnd = source.indexOf('class _AdminNotesPanel', panelStart);
      expect(panelStart, isNonNegative);
      expect(panelEnd, greaterThan(panelStart));
      final panelSource = source.substring(panelStart, panelEnd);

      expect(panelSource, contains('_chatSenderLabel(message)'));
      expect(panelSource, contains('senderDisplayName'));
      expect(panelSource, contains('Circum Support'));
      expect(panelSource, contains("return 'Sender';"));
      expect(panelSource, isNot(contains("message['senderId'] ??")));
    });

    test('operations timeline and incidents use bounded backend projections',
        () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();
      expect(source, contains("collection('timeline')"));
      expect(source, contains('.orderBy(\'timestamp\', descending: true)'));
      expect(source, contains('.limit(_pageSize)'));
      expect(source, contains('startAfterDocument'));
      expect(source, contains("collection('operationalIncidents')"));
      expect(source, contains("httpsCallable(callable)"));
      expect(source, contains("'acknowledgeOperationalIncident'"));
      expect(source, contains("'resolveOperationalIncident'"));
      expect(source, isNot(contains("const steps = [\n      ('Booking'")));
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
          'Parcel Intelligence',
          'Item Library',
          'Parcel Reviews',
          'Operations Centre',
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
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();
      expect(source, contains('Recovery Matrix'));
      expect(source, contains('Super Admin callable with audit'));
      expect(source, contains('No raw record editing or user impersonation'));
      expect(source, contains('Pipeline Health Reset'));
      expect(source, contains('Operations Health Centre'));
      expect(source, contains("httpsCallable('operationsHealthScan')"));
      expect(source, contains("httpsCallable('operationsHealthRepair')"));
      expect(source, contains("httpsCallable('liveDeliveryDiagnostics')"));
      expect(source, contains('Operations Health Scan'));
      expect(source, contains('Health Repair'));
      expect(source, contains('Live Delivery Diagnostics'));
      expect(source, contains("httpsCallable('pipelineHealthReset')"));
      expect(source, contains('This expires only stale unaccepted deliveries'));
      expect(source, contains('Deliveries expired:'));
      expect(source, contains('Before score:'));
      expect(source, contains('After score:'));
      expect(source, contains('force_logout'));
      expect(source, contains('Reconcile'));
      expect(AdminModule.values, contains(AdminModule.irisRepository));
      expect(AdminModule.values, contains(AdminModule.irisCandidates));
      expect(AdminModule.values, contains(AdminModule.gifts));
      expect(
        AdminModule.values.map((module) => module.label),
        isNot(contains('Gift Brand Partners')),
      );
      expect(
        AdminModule.values.map((module) => module.label),
        isNot(contains('Gift Team Workspace')),
      );
      expect(
        AdminModule.values.map((module) => module.label),
        isNot(contains('Gift Story Media')),
      );
      expect(
        AdminModule.values.map((module) => module.label),
        isNot(contains('Gift Campaign Matches')),
      );
    });

    test('restores historical IRIS and Gifts flow transitions', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();
      final backend = File(
        'server/functions/admin-operations-authority.js',
      ).readAsStringSync();

      expect(source, contains('New Canonical Item'));
      expect(
        source,
        contains('Future<Map<String, Object?>?> _irisRepositoryEditPatch'),
      );
      expect(source, contains('Alias Manager'));
      expect(source, contains('Category Management'));
      expect(source, contains('Imports and Repository Settings'));
      expect(
          source, contains("httpsCallable('adminUpdateIrisRepositoryRecord')"));
      expect(
        source,
        isNot(contains("collection('irisCanonicalObjects').doc(canonicalId)")),
      );
      expect(backend, contains('repositoryPromotionStatus: "committed"'));
      expect(
        backend,
        contains(
          'Candidate promoted to Canonical Repository from Admin',
        ),
      );

      expect(source, contains('Gift Brand Partners'));
      expect(source, contains('Brand Partner Directory'));
      expect(source, contains('Partner Profiles and History'));
      expect(source, contains('Future<void> _setGiftBrandStatus'));
      expect(source, contains('Future<void> _editGiftBrandPartner'));

      expect(source, contains('Future<void> _suggestGiftCampaignMatch'));
      expect(source, contains('Future<void> _approveGiftCampaignMatch'));
      expect(source, contains('Future<void> _bulkGiftCampaignAction'));
      expect(
          source, contains("httpsCallable('adminSuggestGiftCampaignMatch')"));
      expect(
          source, contains("httpsCallable('adminApproveGiftCampaignMatch')"));
      expect(source, contains("httpsCallable('adminBulkGiftCampaignAction')"));
      expect(
        source,
        isNot(contains("collection('giftCampaignMatches').doc(matchId)")),
      );
      expect(source, isNot(contains("collection('giftRequests').doc()")));
      expect(backend, contains('gift_campaign_match_approved'));
      expect(source, contains('Export selected'));

      expect(source, contains('Future<void> _editGiftRequestWorkflow'));
      expect(source, contains('Gift Request Editor'));
      expect(source, contains('procurementOrderReference'));
      expect(source, contains('giftStoryPhotoUrls'));
      expect(source, contains('giftStoryCustomAudioUrl'));
      expect(source, contains("httpsCallable('recordGiftStoryEvent')"));
      expect(source, contains("httpsCallable('updateGiftStoryPrivacy')"));
      expect(source, contains('contentStatus'));
      expect(source, contains('captionDraft'));
      expect(source, contains('postedTikTokUrl'));
      expect(source, contains("httpsCallable('adminSaveGiftRequestEditor')"));
      expect(backend, contains('gift_request_editor_saved'));
    });

    test('Gifts Admin is split into three operational workspaces', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();

      expect(source, contains("workflow('Gifts Workflow'"));
      expect(source, contains("campaigns('Campaigns'"));
      expect(source, contains("brandPartners('Brand Partners'"));
      expect(source, contains('People-Led Gifts Workspace'));
      expect(source, contains('People Queue'));
      expect(source, contains('Gift Creation Studio'));
      expect(source, contains('Story Studio'));
      expect(source, contains('Campaign Operations'));
      expect(source, contains('Brand Partner Directory'));
      expect(source, contains('IRIS Intelligence'));
      expect(source, contains('Voice Notes'));
      expect(source, contains('Ready for Dispatch'));
    });

    test('Business invoices are generated through Admin backend authority', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();

      expect(source, contains('Future<void> _createBusinessInvoice'));
      expect(source, contains("httpsCallable('adminCreateBusinessInvoice')"));
      expect(source, contains('Generate invoice'));
      expect(source, contains('Reason'));
    });

    test('Recognition operations use existing backend authority and audit', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();

      expect(AdminModule.values, contains(AdminModule.recognition));
      expect(source, contains('Recognition Management'));
      expect(source, contains('Recognition Audit Trail'));
      expect(source, contains("'grantRecognition'"));
      expect(source, contains("'revokeRecognition'"));
      expect(source, contains("collection('recognitionAwards')"));
      expect(source, contains("collection('recognitionAuditLogs')"));
      expect(
        source,
        contains(r"actionType: 'recognition_${action}_requested'"),
      );
      expect(source, contains('Reason'));
    });

    test(
      'IRIS referral queue exposes referral resolution without IRIS rewrites',
      () {
        final source = File(
          'lib/app/admin/admin_phase1_shell.dart',
        ).readAsStringSync();

        expect(source, contains('IRIS Referrals Queue'));
        expect(source, contains('referral_required'));
        expect(source, contains('unsupported'));
        expect(source, contains('prohibited'));
        expect(source, contains('_isIrisReferralRecord'));
        expect(source, contains("httpsCallable('adjudicateIris')"));
        expect(source, contains('onAdjudicateIrisReferral(record'));
      },
    );

    test('Manual Roth credit remains behind backend callable with reason', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();

      expect(source, contains('Manual Roth Credit'));
      expect(source, contains('Future<void> _issueManualRothCredit'));
      expect(source, contains("httpsCallable('issueRothToWallets')"));
      expect(source, contains('manual_roth_credit_requested'));
      expect(source, contains('Recipient, amount and reason are required.'));
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
      expect(data.messageReports, isEmpty);
      expect(data.adminNotes, isEmpty);
      expect(data.senderTrustEvents, isEmpty);
      expect(data.irisReferenceImages, isEmpty);
      expect(data.healthPlusProfiles, isEmpty);
      expect(data.driverPerformanceMetrics, isEmpty);
    });

    test(
      'restores historical operational depth for Business Rider and Health+',
      () {
        final source = File(
          'lib/app/admin/admin_phase1_shell.dart',
        ).readAsStringSync();
        final operations = File(
          'lib/app/admin/admin_operations.dart',
        ).readAsStringSync();

        expect(source, contains("collection('healthPlusProfiles')"));
        expect(source, contains('Health+ Profile Workspace'));
        expect(source, contains('Future<void> _updateHealthPlusProfile'));
        expect(source, contains('medical profile viewer'));
        expect(source, contains('operational history'));

        for (final section in const [
          'Business Companies',
          'Business Members',
          'Business Deliveries',
          'Business Health+',
          'Business Gifts',
          'Business Vanguard',
          'Business Invoices',
          'Business Roth',
          'Business Analytics',
          'Business Audit Log',
        ]) {
          expect(source, contains(section));
        }
        expect(source, contains('Future<void> _changeBusinessMemberRole'));
        expect(source, contains('Future<void> _removeBusinessMember'));
        expect(source, contains('roth_credit_review'));
        expect(operations, contains('rothReviewStatus'));

        expect(source, contains('Rider Performance Metrics'));
        expect(source, contains('driverPerformanceMetrics'));
        expect(source, contains('acceptance'));
        expect(source, contains('Rider operational history'));
        expect(source, contains('performance_review'));
        expect(source, contains('warning_issued'));
      },
    );

    test('restores historical Admin final-gap backend surfaces', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();

      expect(source, contains("httpsCallable('resolveStaleDeliveryLock')"));
      expect(source, contains("httpsCallable('sendCircumAnnouncement')"));
      expect(source, contains("collection('messageReports')"));
      expect(source, contains("httpsCallable('getIrisReferenceImage')"));
      expect(source, contains("httpsCallable('finalizeIrisReferenceImage')"));
      expect(source, contains("httpsCallable('deleteIrisReferenceImage')"));
      expect(source, contains('Stale Delivery Lock Queue'));
      expect(source, contains('Message Report Queue'));
      expect(source, contains('Announcement Composer'));
      expect(source, contains('IRIS Reference Image Lifecycle'));
    });

    test(
      'Admin IRIS learning queue includes canonical and legacy candidates',
      () {
        final source = File(
          'lib/app/admin/admin_phase1_shell.dart',
        ).readAsStringSync();

        expect(source, contains("collection('irisLearningCases')"));
        expect(
          source,
          contains("collection('iris_learning_review_candidates')"),
        );
        expect(source, contains("'iris_learning_review_candidates'"));
      },
    );

    test('Admin IRIS action buttons do not use empty callbacks', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('onPressed: () {}')));
      expect(source, isNot(contains('onPressed: () => null')));
    });

    test('restores Vanguard enhanced custody Admin review path', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();

      expect(source, contains('Enhanced Custody Review'));
      expect(source, contains('Chain of custody'));
      expect(source, contains('Collection evidence'));
      expect(source, contains('Transfer evidence'));
      expect(source, contains('Drop-off evidence'));
      expect(source, contains('Flag custody concern'));
      expect(source, contains('Request custody evidence'));
      expect(source, contains('vanguard_custody_closed'));
    });

    test('restores final historical Admin support and trust surfaces', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();

      expect(
        source,
        contains("httpsCallable('getOrCreateSupportConversation')"),
      );
      expect(source, contains("httpsCallable('startAdminConversation')"));
      expect(
        source,
        contains("httpsCallable('updateSupportConversationStatus')"),
      );
      expect(source, contains("collection('adminNotes')"));
      expect(source, contains("collection('senderTrustEvents')"));
      expect(source, contains("httpsCallable('adminUpdateSenderTrust')"));
      expect(source, contains(".collection('messages')"));
      expect(source, contains('Message Rider'));
      expect(source, contains('Open chat'));
      expect(source, contains('Internal Admin Notes'));
      expect(source, contains('Conversation History'));
      expect(source, contains('Sender Trust Timeline'));
      expect(source, contains('Award trust'));
      expect(source, contains('Freeze trust'));
    });

    test('keeps Sender trust authority behind backend callable', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf('Future<void> _updateSenderTrust');
      final methodEnd = source.indexOf('Future<void> _resolveMessageReport');
      expect(methodStart, isNonNegative);
      expect(methodEnd, greaterThan(methodStart));
      final method = source.substring(methodStart, methodEnd);

      expect(method, contains("httpsCallable('adminUpdateSenderTrust')"));
      expect(method, isNot(contains('runTransaction')));
      expect(method, isNot(contains("collection('users').doc(senderId)")));
      expect(method, isNot(contains("collection('senderTrustEvents').doc()")));
    });

    test('restores Admin notification delivery operations', () {
      final source = File(
        'lib/app/admin/admin_phase1_shell.dart',
      ).readAsStringSync();

      expect(source, contains("collection('notifications')"));
      expect(source, contains("httpsCallable('retryNotificationDelivery')"));
      expect(source, contains('Notification Operations'));
      expect(source, contains('pushDeliveryStatus'));
      expect(source, contains('failureReason'));
      expect(source, contains('bool _notificationNeedsRetry'));
      expect(source, contains('Retry'));
    });
  });
}
