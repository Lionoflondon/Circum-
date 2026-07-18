enum AdminRole {
  superAdmin('super_admin'),
  operationsAdmin('operations_admin'),
  supportAgent('support_agent'),
  financeAdmin('finance_admin'),
  driverManager('driver_manager');

  final String value;

  const AdminRole(this.value);

  static AdminRole? fromString(String? value) {
    for (final role in AdminRole.values) {
      if (role.value == value) return role;
    }
    return null;
  }
}

enum AdminPermission {
  viewDashboard,
  manageAdmins,
  viewCustomers,
  editCustomers,
  viewDrivers,
  editDrivers,
  approveDrivers,
  manageDriverRanks,
  viewDeliveries,
  editDeliveries,
  duplicateDeliveries,
  viewFinance,
  manageFinance,
  viewHealthPlus,
  manageHealthPlus,
  viewSupport,
  manageIssues,
  viewAudit,
}

class AdminAccessPolicy {
  static const _rolePermissions = {
    AdminRole.superAdmin: AdminPermission.values,
    AdminRole.operationsAdmin: [
      AdminPermission.viewDashboard,
      AdminPermission.viewCustomers,
      AdminPermission.editCustomers,
      AdminPermission.viewDrivers,
      AdminPermission.viewDeliveries,
      AdminPermission.editDeliveries,
      AdminPermission.duplicateDeliveries,
      AdminPermission.viewHealthPlus,
      AdminPermission.manageHealthPlus,
      AdminPermission.viewSupport,
      AdminPermission.manageIssues,
      AdminPermission.viewAudit,
    ],
    AdminRole.supportAgent: [
      AdminPermission.viewDashboard,
      AdminPermission.viewCustomers,
      AdminPermission.editCustomers,
      AdminPermission.viewDrivers,
      AdminPermission.viewDeliveries,
      AdminPermission.viewSupport,
      AdminPermission.manageIssues,
      AdminPermission.viewAudit,
    ],
    AdminRole.financeAdmin: [
      AdminPermission.viewDashboard,
      AdminPermission.viewCustomers,
      AdminPermission.viewDrivers,
      AdminPermission.viewDeliveries,
      AdminPermission.viewFinance,
      AdminPermission.manageFinance,
      AdminPermission.viewHealthPlus,
      AdminPermission.viewAudit,
    ],
    AdminRole.driverManager: [
      AdminPermission.viewDashboard,
      AdminPermission.viewDrivers,
      AdminPermission.editDrivers,
      AdminPermission.approveDrivers,
      AdminPermission.manageDriverRanks,
      AdminPermission.viewDeliveries,
      AdminPermission.viewHealthPlus,
      AdminPermission.viewSupport,
      AdminPermission.manageIssues,
      AdminPermission.viewAudit,
    ],
  };

  static bool hasAnyAdminRole(Iterable<String> roles) {
    return roles.any((role) => AdminRole.fromString(role) != null);
  }

  static bool can(Iterable<String> roles, AdminPermission permission) {
    for (final rawRole in roles) {
      final role = AdminRole.fromString(rawRole);
      if (role == null) continue;
      if ((_rolePermissions[role] ?? const []).contains(permission)) {
        return true;
      }
    }
    return false;
  }
}

class AdminFinanceTools {
  static const workflowStatuses = [
    'review_assigned',
    'reconciled',
    'escalated',
    'wallet_credit_review',
    'wallet_debit_review',
    'roth_issue_review',
    'roth_remove_review',
    'refund_approved',
    'refund_rejected',
    'investigation_flagged',
    'investigation_resolved',
  ];

  static Map<String, dynamic> workflowPatch({
    required String status,
    required String updatedBy,
    required Object updatedAt,
    String? note,
  }) {
    if (!workflowStatuses.contains(status)) {
      throw ArgumentError('Unsupported finance workflow status.');
    }
    return {
      'financeReviewStatus': status,
      'financeReviewedBy': updatedBy,
      'financeReviewedAt': updatedAt,
      'financeEscalated': status == 'escalated',
      if (status.contains('refund')) 'refundReviewStatus': status,
      if (status.contains('investigation')) 'investigationStatus': status,
      if (status.contains('wallet')) 'walletReviewStatus': status,
      if (status.contains('roth')) 'rothReviewStatus': status,
      if (note?.trim().isNotEmpty == true) 'financeNote': note!.trim(),
    };
  }
}

class AdminIrisOperationsTools {
  static const reviewStatuses = [
    'approved',
    'rejected',
    'weight_override_review',
    'category_override_review',
    'vehicle_override_review',
    'more_evidence_requested',
    'engineering_review',
    'learning_flagged',
    'closed',
  ];

  static Map<String, dynamic> reviewPatch({
    required String status,
    required String updatedBy,
    required Object updatedAt,
    required String reason,
  }) {
    if (!reviewStatuses.contains(status)) {
      throw ArgumentError('Unsupported IRIS review status.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('An IRIS review reason is required.');
    }
    return {
      'irisReviewStatus': status,
      'irisReviewedBy': updatedBy,
      'irisReviewedAt': updatedAt,
      'irisReviewReason': reason.trim(),
      if (status == 'learning_flagged') 'irisLearningQueueStatus': 'pending',
      if (status == 'engineering_review') 'engineeringReviewStatus': 'open',
      if (status == 'more_evidence_requested')
        'evidenceRequestStatus': 'requested',
      if (status == 'closed') 'irisReviewClosed': true,
    };
  }
}

class AdminAccountTools {
  static const accountStatuses = [
    'active',
    'suspended',
    'reactivated',
    'closure_review',
  ];

  static Map<String, dynamic> accountStatusPatch({
    required String status,
    required String updatedBy,
    required Object updatedAt,
    String? reason,
  }) {
    if (!accountStatuses.contains(status)) {
      throw ArgumentError('Unsupported account status.');
    }
    return {
      'accountStatus': status,
      'status': status == 'reactivated' ? 'active' : status,
      'adminStatusUpdatedBy': updatedBy,
      'adminStatusUpdatedAt': updatedAt,
      if (reason?.trim().isNotEmpty == true)
        'adminStatusReason': reason!.trim(),
      if (status == 'closure_review') 'closureReviewStatus': 'requested',
    };
  }

  static Map<String, dynamic> businessStatusPatch({
    required String status,
    required String updatedBy,
    required Object updatedAt,
  }) {
    if (!['approved', 'rejected', 'suspended', 'reactivated']
        .contains(status)) {
      throw ArgumentError('Unsupported business account status.');
    }
    return {
      'status': status == 'reactivated' ? 'approved' : status,
      'verificationStatus': status == 'approved' ? 'approved' : status,
      'adminStatusUpdatedBy': updatedBy,
      'adminStatusUpdatedAt': updatedAt,
    };
  }

  static Map<String, dynamic> mergeReviewRecord({
    required String primaryAccountId,
    required String duplicateAccountId,
    required String requestedBy,
    required Object createdAt,
  }) {
    if (primaryAccountId.trim().isEmpty || duplicateAccountId.trim().isEmpty) {
      throw ArgumentError('Both accounts are required.');
    }
    if (primaryAccountId.trim() == duplicateAccountId.trim()) {
      throw ArgumentError('Duplicate account must be different.');
    }
    return {
      'primaryAccountId': primaryAccountId.trim(),
      'duplicateAccountId': duplicateAccountId.trim(),
      'status': 'pending_review',
      'requestedBy': requestedBy,
      'createdAt': createdAt,
      'source': 'circum-admin',
    };
  }
}

class AdminRiderOperationsTools {
  static const riderStatuses = [
    'approved',
    'rejected',
    'suspended',
    'reactivated',
    'documents_requested',
    'documents_approved',
    'documents_rejected',
    'under_investigation',
    'investigation_cleared',
  ];

  static Map<String, dynamic> statusPatch({
    required String status,
    required String updatedBy,
    required Object updatedAt,
    required String reason,
  }) {
    if (!riderStatuses.contains(status)) {
      throw ArgumentError('Unsupported rider operation status.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('A rider operation reason is required.');
    }
    final driverStatus = switch (status) {
      'approved' || 'reactivated' || 'investigation_cleared' => 'active',
      'rejected' => 'rejected',
      'suspended' => 'suspended',
      'under_investigation' => 'under_investigation',
      _ => null,
    };
    return {
      'adminOperationStatus': status,
      'adminOperationReason': reason.trim(),
      'adminOperationUpdatedBy': updatedBy,
      'adminOperationUpdatedAt': updatedAt,
      if (driverStatus != null) 'driverStatus': driverStatus,
      if (status == 'approved' || status == 'reactivated')
        'approvalStatus': 'approved',
      if (status == 'rejected') 'approvalStatus': 'rejected',
      if (status == 'documents_requested') 'documentReviewStatus': 'requested',
      if (status == 'documents_approved') 'documentReviewStatus': 'approved',
      if (status == 'documents_rejected') 'documentReviewStatus': 'rejected',
      if (status == 'under_investigation') 'investigationStatus': 'open',
      if (status == 'investigation_cleared') 'investigationStatus': 'cleared',
      'updatedAt': updatedAt,
    };
  }
}

class AdminDeliveryOperationsTools {
  static const operationStatuses = [
    'paused',
    'resumed',
    'escalated',
    'cancel_review',
    'force_complete_review',
    'archive_review',
    'waiting_review',
    'no_show_review',
    'iris_review_override',
    'fraud_flagged',
  ];

  static Map<String, dynamic> operationPatch({
    required String status,
    required String updatedBy,
    required Object updatedAt,
    required String reason,
  }) {
    if (!operationStatuses.contains(status)) {
      throw ArgumentError('Unsupported delivery operation status.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('A delivery operation reason is required.');
    }
    return {
      'adminOperationStatus': status,
      'adminOperationReason': reason.trim(),
      'adminOperationUpdatedBy': updatedBy,
      'adminOperationUpdatedAt': updatedAt,
      if (status == 'paused') 'adminPaused': true,
      if (status == 'resumed') 'adminPaused': false,
      if (status == 'escalated') 'escalationStatus': 'open',
      if (status == 'waiting_review') 'waitingReviewStatus': 'open',
      if (status == 'no_show_review') 'noShowReviewStatus': 'open',
      if (status == 'iris_review_override') 'irisReviewStatus': 'admin_review',
      if (status == 'fraud_flagged') 'fraudReviewStatus': 'flagged',
    };
  }
}

class RiderRankPolicy {
  static const ranks = ['agent', 'sentinel', 'warden', 'knight', 'veteran'];

  static String normalize(Object? value) {
    final rank = '$value'.trim().toLowerCase();
    return ranks.contains(rank) ? rank : 'agent';
  }

  static String fromProfile(Map<String, dynamic> profile) {
    return normalize(profile['rank'] ?? profile['riderRank']);
  }

  static bool canManage(Iterable<String> roles) {
    return roles.contains(AdminRole.superAdmin.value) ||
        roles.contains(AdminRole.driverManager.value);
  }

  static Map<String, dynamic> updatePatch({
    required String rank,
    required Object updatedAt,
    required String updatedBy,
    required String reason,
  }) {
    if (reason.trim().isEmpty) {
      throw ArgumentError('A rank change reason is required.');
    }
    final normalized = normalize(rank);
    return {
      'rank': normalized,
      'riderRank': normalized,
      'rankUpdatedAt': updatedAt,
      'rankUpdatedBy': updatedBy,
      'rankReason': reason.trim(),
      'updatedAt': updatedAt,
    };
  }
}

class AdminUserAccess {
  static List<String> activeRolesFromRecord(Map<String, dynamic>? record) {
    if (record == null || !isActive(record)) return const [];
    final roles = record['roles'];
    if (roles is List) return roles.map((role) => '$role').toList();
    final role = record['role'];
    return role == null ? const [] : ['$role'];
  }

  static bool isActive(Map<String, dynamic>? record) {
    return '${record?['status'] ?? 'inactive'}'.toLowerCase() == 'active';
  }

  static bool hasInactiveAdminRecord(Iterable<Map<String, dynamic>?> records) {
    return records
        .where((record) => record != null)
        .any((record) => !isActive(record));
  }

  static String emailDocumentId(String email) => email.trim().toLowerCase();

  static Map<String, dynamic> adminUserPatch({
    required String email,
    required String role,
    required String status,
    required String invitedBy,
    Object? createdAt,
    required Object updatedAt,
    Object? lastLoginAt,
  }) {
    return {
      'email': email.trim().toLowerCase(),
      'role': role,
      'roles': [role],
      'status': status,
      'invitedBy': invitedBy,
      if (createdAt != null) 'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (lastLoginAt != null) 'lastLoginAt': lastLoginAt,
    };
  }
}

class AdminMetricSnapshot {
  final int totalDeliveries;
  final int activeDeliveries;
  final int completedDeliveries;
  final int failedDeliveries;
  final int cancelledDeliveries;
  final int totalSenders;
  final int activeSenders;
  final int totalDrivers;
  final int activeDrivers;
  final int pendingDrivers;
  final double revenueToday;
  final double revenueThisWeek;
  final double revenueThisMonth;
  final double averageDeliveryValue;
  final double averageDriverRating;
  final double customerSatisfactionScore;
  final int complaintsCount;
  final int refundRequests;
  final int unresolvedSupportIssues;
  final double cancellationRate;
  final double failedDeliveryRate;
  final double repeatCustomerRate;
  final double refundRate;
  final double healthPlusRecurringRevenue;

  const AdminMetricSnapshot({
    required this.totalDeliveries,
    required this.activeDeliveries,
    required this.completedDeliveries,
    required this.failedDeliveries,
    required this.cancelledDeliveries,
    required this.totalSenders,
    required this.activeSenders,
    required this.totalDrivers,
    required this.activeDrivers,
    required this.pendingDrivers,
    required this.revenueToday,
    required this.revenueThisWeek,
    required this.revenueThisMonth,
    required this.averageDeliveryValue,
    required this.averageDriverRating,
    required this.customerSatisfactionScore,
    required this.complaintsCount,
    required this.refundRequests,
    required this.unresolvedSupportIssues,
    required this.cancellationRate,
    required this.failedDeliveryRate,
    required this.repeatCustomerRate,
    required this.refundRate,
    required this.healthPlusRecurringRevenue,
  });

  factory AdminMetricSnapshot.fromData({
    required List<Map<String, dynamic>> deliveries,
    required List<Map<String, dynamic>> senders,
    required List<Map<String, dynamic>> drivers,
    required List<Map<String, dynamic>> payments,
    required List<Map<String, dynamic>> ratings,
    required List<Map<String, dynamic>> supportTickets,
    required List<Map<String, dynamic>> healthPlusPayments,
    DateTime? now,
  }) {
    final today = _dayStart(now ?? DateTime.now());
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final monthStart = DateTime(today.year, today.month);
    final completed = deliveries.where(_isCompleted).toList();
    final failed = deliveries.where(_isFailed).toList();
    final cancelled = deliveries.where(_isCancelled).toList();
    final active = deliveries
        .where((item) =>
            !_isCompleted(item) && !_isFailed(item) && !_isCancelled(item))
        .toList();
    final revenueToday = _sumSince(payments, today);
    final revenueThisWeek = _sumSince(payments, weekStart);
    final revenueThisMonth = _sumSince(payments, monthStart);
    final totalRevenue = payments.fold<double>(
      0,
      (total, item) => total + _moneyValue(item),
    );
    final averageRating = ratings.isEmpty
        ? 0.0
        : ratings.fold<double>(
              0,
              (total, rating) => total + _number(rating['starRating']),
            ) /
            ratings.length;
    final uniqueSenders = <String>{};
    final repeatSenders = <String>{};
    for (final delivery in deliveries) {
      final senderId = '${delivery['senderId'] ?? delivery['userId'] ?? ''}';
      if (senderId.trim().isEmpty) continue;
      if (!uniqueSenders.add(senderId)) repeatSenders.add(senderId);
    }

    return AdminMetricSnapshot(
      totalDeliveries: deliveries.length,
      activeDeliveries: active.length,
      completedDeliveries: completed.length,
      failedDeliveries: failed.length,
      cancelledDeliveries: cancelled.length,
      totalSenders: senders.length,
      activeSenders: senders.where((item) => !_isInactive(item)).length,
      totalDrivers: drivers.length,
      activeDrivers: drivers.where((item) => _isActiveDriver(item)).length,
      pendingDrivers: drivers.where((item) => _isPendingDriver(item)).length,
      revenueToday: _round2(revenueToday),
      revenueThisWeek: _round2(revenueThisWeek),
      revenueThisMonth: _round2(revenueThisMonth),
      averageDeliveryValue:
          completed.isEmpty ? 0 : _round2(totalRevenue / completed.length),
      averageDriverRating: _round2(averageRating),
      customerSatisfactionScore: _round2((averageRating / 5) * 100),
      complaintsCount: ratings
          .where((rating) =>
              '${rating['feedbackTags']}'.contains('issue') ||
              '${rating['feedbackTags']}'.contains('damaged'))
          .length,
      refundRequests: supportTickets
          .where((ticket) => '${ticket['type']}'.contains('refund'))
          .length,
      unresolvedSupportIssues:
          supportTickets.where((ticket) => !_isResolved(ticket)).length,
      cancellationRate: _rate(cancelled.length, deliveries.length),
      failedDeliveryRate: _rate(failed.length, deliveries.length),
      repeatCustomerRate: _rate(repeatSenders.length, uniqueSenders.length),
      refundRate: _rate(
        supportTickets
            .where((ticket) => '${ticket['type']}'.contains('refund'))
            .length,
        deliveries.length,
      ),
      healthPlusRecurringRevenue: _round2(
        healthPlusPayments
            .where((item) =>
                '${item['frequency']}'.contains('monthly') ||
                item['recurring'] == true ||
                item['savedPaymentMethod'] == true)
            .fold<double>(0, (total, item) => total + _moneyValue(item)),
      ),
    );
  }

  static AdminMetricSnapshot empty() => const AdminMetricSnapshot(
        totalDeliveries: 0,
        activeDeliveries: 0,
        completedDeliveries: 0,
        failedDeliveries: 0,
        cancelledDeliveries: 0,
        totalSenders: 0,
        activeSenders: 0,
        totalDrivers: 0,
        activeDrivers: 0,
        pendingDrivers: 0,
        revenueToday: 0,
        revenueThisWeek: 0,
        revenueThisMonth: 0,
        averageDeliveryValue: 0,
        averageDriverRating: 0,
        customerSatisfactionScore: 0,
        complaintsCount: 0,
        refundRequests: 0,
        unresolvedSupportIssues: 0,
        cancellationRate: 0,
        failedDeliveryRate: 0,
        repeatCustomerRate: 0,
        refundRate: 0,
        healthPlusRecurringRevenue: 0,
      );
}

class AdminPlatformAlert {
  const AdminPlatformAlert({
    required this.severity,
    required this.title,
    required this.detail,
  });

  final String severity;
  final String title;
  final String detail;
}

class AdminPlatformHealthSnapshot {
  const AdminPlatformHealthSnapshot({
    required this.activeJobs,
    required this.waitingJobs,
    required this.vanguardJobs,
    required this.discrepancyReviews,
    required this.walletReviewItems,
    required this.supportOpen,
    required this.healthPlusOpen,
    required this.businessPending,
    required this.giftsPending,
    required this.alerts,
  });

  final int activeJobs;
  final int waitingJobs;
  final int vanguardJobs;
  final int discrepancyReviews;
  final int walletReviewItems;
  final int supportOpen;
  final int healthPlusOpen;
  final int businessPending;
  final int giftsPending;
  final List<AdminPlatformAlert> alerts;

  String get status {
    if (alerts.any((alert) => alert.severity == 'critical')) return 'Critical';
    if (alerts.any((alert) => alert.severity == 'warning')) return 'Watch';
    return 'Healthy';
  }

  factory AdminPlatformHealthSnapshot.fromData({
    required List<Map<String, dynamic>> deliveries,
    required List<Map<String, dynamic>> payments,
    required List<Map<String, dynamic>> supportTickets,
    required List<Map<String, dynamic>> healthPlusPickups,
    required List<Map<String, dynamic>> businessAccounts,
    required List<Map<String, dynamic>> giftOrders,
  }) {
    final activeDeliveries = deliveries
        .where((item) =>
            !_isCompleted(item) && !_isFailed(item) && !_isCancelled(item))
        .toList();
    final waiting = activeDeliveries
        .where((item) => _hasStatus(item, const [
              'waiting',
              'no_show',
              'no-show',
            ]))
        .length;
    final vanguard = activeDeliveries
        .where((item) => _containsAny(item, const ['vanguard']))
        .length;
    final discrepancies = deliveries
        .where((item) => _containsAny(item, const [
              'discrepancy',
              'adjustment_pending',
              'awaiting_review',
              'iris_review'
            ]))
        .length;
    final financeReview = payments
        .where((item) => _containsAny(item, const [
              'review',
              'refund',
              'dispute',
              'escalated',
              'pending_verification'
            ]))
        .length;
    final supportOpen =
        supportTickets.where((ticket) => !_isResolved(ticket)).length;
    final healthOpen = healthPlusPickups
        .where((item) =>
            !_containsAny(item, const ['completed', 'cancelled', 'closed']))
        .length;
    final businessPending = businessAccounts
        .where((item) => _containsAny(item, const ['pending', 'review']))
        .length;
    final giftsPending = giftOrders
        .where((item) => _containsAny(item, const ['pending', 'review']))
        .length;
    final alerts = <AdminPlatformAlert>[
      if (supportOpen > 0)
        AdminPlatformAlert(
          severity: supportOpen > 5 ? 'critical' : 'warning',
          title: 'Support queue',
          detail: '$supportOpen unresolved support tickets',
        ),
      if (discrepancies > 0)
        AdminPlatformAlert(
          severity: 'warning',
          title: 'IRIS and parcel review',
          detail: '$discrepancies discrepancy reviews need attention',
        ),
      if (financeReview > 0)
        AdminPlatformAlert(
          severity: 'warning',
          title: 'Finance review',
          detail: '$financeReview payment or wallet items need review',
        ),
      if (waiting > 0)
        AdminPlatformAlert(
          severity: 'warning',
          title: 'Waiting/no-show jobs',
          detail: '$waiting active deliveries may need operator action',
        ),
      if (healthOpen > 0)
        AdminPlatformAlert(
          severity: 'info',
          title: 'Health+ operations',
          detail: '$healthOpen active prescription pickups',
        ),
    ];
    return AdminPlatformHealthSnapshot(
      activeJobs: activeDeliveries.length,
      waitingJobs: waiting,
      vanguardJobs: vanguard,
      discrepancyReviews: discrepancies,
      walletReviewItems: financeReview,
      supportOpen: supportOpen,
      healthPlusOpen: healthOpen,
      businessPending: businessPending,
      giftsPending: giftsPending,
      alerts: alerts,
    );
  }
}

class AdminAuditEntry {
  final String adminUserId;
  final String actionType;
  final String recordType;
  final String recordId;
  final Map<String, dynamic> oldValue;
  final Map<String, dynamic> newValue;
  final String reason;

  const AdminAuditEntry({
    required this.adminUserId,
    required this.actionType,
    required this.recordType,
    required this.recordId,
    this.oldValue = const {},
    this.newValue = const {},
    this.reason = '',
  });

  Map<String, dynamic> toJson() => {
        'adminUserId': adminUserId,
        'actionType': actionType,
        'recordType': recordType,
        'recordId': recordId,
        'oldValue': oldValue,
        'newValue': newValue,
        'reason': reason,
      };
}

bool _containsAny(Map<String, dynamic> record, List<String> needles) {
  final value = record.entries
      .where((entry) => entry.value is! Map && entry.value is! List)
      .map((entry) => '${entry.key}:${entry.value}'.toLowerCase())
      .join(' ');
  return needles.any(value.contains);
}

bool _hasStatus(Map<String, dynamic> record, List<String> statuses) {
  final values = [
    record['status'],
    record['deliveryStatus'],
    record['deliveryStage'],
    record['trackingStatus'],
  ].map((value) => '$value'.trim().toLowerCase());
  return values.any(statuses.contains);
}

class AdminDeliveryTools {
  static Map<String, dynamic> duplicateDelivery(
    Map<String, dynamic> source, {
    required String newId,
    required Object createdAt,
  }) {
    final copy = Map<String, dynamic>.from(source);
    copy
      ..remove('historyId')
      ..remove('driverRatingId')
      ..remove('ratedAt')
      ..remove('proofOfDelivery')
      ..['requestId'] = newId
      ..['status'] = 'requested'
      ..['dispatchStatus'] = 'requested'
      ..['matchingStatus'] = 'available'
      ..['createdAt'] = createdAt
      ..['updatedAt'] = createdAt
      ..['source'] = '${source['source'] ?? 'circum'}-admin-duplicate'
      ..['adminDuplicatedFrom'] = source['requestId'] ?? source['id'];
    return copy;
  }

  static Map<String, dynamic> safeDeliveryPatch({
    String? pickupAddress,
    String? dropoffAddress,
    String? parcelNotes,
    String? pickupTime,
    String? senderPhone,
    String? recipientPhone,
  }) {
    return {
      if (pickupAddress != null) 'pickupAddress': pickupAddress,
      if (dropoffAddress != null) 'dropoffAddress': dropoffAddress,
      if (parcelNotes != null) 'packageDescription': parcelNotes,
      if (pickupTime != null) 'pickupTime': pickupTime,
      if (senderPhone != null) 'senderPhone': senderPhone,
      if (recipientPhone != null) 'recipientPhone': recipientPhone,
    };
  }
}

class AdminSupportTools {
  static bool isResolved(Object? status) =>
      '${status ?? ''}'.trim().toLowerCase() == 'resolved';

  static List<String> actionsForStatus(Object? status) => isResolved(status)
      ? const ['Reopen', 'View Chat']
      : const ['Assign', 'Resolve', 'Open Chat'];

  static Map<String, dynamic> statusPatch({
    required String status,
    String? assignedTo,
    String? resolutionNote,
    required Object updatedAt,
  }) {
    return {
      'status': status,
      if (assignedTo != null && assignedTo.trim().isNotEmpty)
        'assignedTo': assignedTo.trim(),
      if (resolutionNote != null && resolutionNote.trim().isNotEmpty)
        'resolutionNote': resolutionNote.trim(),
      'updatedAt': updatedAt,
    };
  }
}

class AdminHealthPlusTools {
  static const operationStatuses = [
    'assigned',
    'collected',
    'completed',
    'pharmacy_assigned',
    'pharmacy_reassigned',
    'rider_assigned',
    'escalated',
    'review_approved',
    'review_rejected',
    'evidence_requested',
    'paused',
    'resumed',
    'closed',
  ];

  static Map<String, dynamic> statusPatch({
    required String status,
    String? assignedDriverId,
    String? updatedBy,
    String? reason,
    required Object updatedAt,
  }) {
    if (!operationStatuses.contains(status)) {
      throw ArgumentError('Unsupported Health+ operation status.');
    }
    return {
      'status': status,
      if (assignedDriverId != null && assignedDriverId.trim().isNotEmpty)
        'assignedDriverId': assignedDriverId.trim(),
      if (updatedBy != null) 'adminUpdatedBy': updatedBy,
      if (reason?.trim().isNotEmpty == true) 'adminReason': reason!.trim(),
      if (status == 'pharmacy_assigned' || status == 'pharmacy_reassigned')
        'pharmacyReviewStatus': status,
      if (status == 'rider_assigned') 'riderAssignmentStatus': 'assigned',
      if (status == 'escalated') 'escalationStatus': 'open',
      if (status == 'review_approved') 'clinicalReviewStatus': 'approved',
      if (status == 'review_rejected') 'clinicalReviewStatus': 'rejected',
      if (status == 'evidence_requested') 'clinicalEvidenceStatus': 'requested',
      if (status == 'paused') 'adminPaused': true,
      if (status == 'resumed') 'adminPaused': false,
      if (status == 'closed') 'caseStatus': 'closed',
      'adminUpdatedAt': updatedAt,
      'updatedAt': updatedAt,
    };
  }
}

class AdminBusinessOperationsTools {
  static const operationStatuses = [
    'verified',
    'manager_assigned',
    'invoice_issue_review',
    'invoice_cancel_review',
    'subscription_adjust_review',
    'subscription_upgrade_review',
    'subscription_downgrade_review',
    'business_close_review',
  ];

  static Map<String, dynamic> operationPatch({
    required String status,
    required String updatedBy,
    required Object updatedAt,
    required String reason,
  }) {
    if (!operationStatuses.contains(status)) {
      throw ArgumentError('Unsupported Business operation status.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('A Business operation reason is required.');
    }
    return {
      'businessOperationStatus': status,
      'businessOperationReason': reason.trim(),
      'businessOperationUpdatedBy': updatedBy,
      'businessOperationUpdatedAt': updatedAt,
      if (status == 'verified') 'verificationStatus': 'approved',
      if (status == 'manager_assigned') 'accountManagerStatus': 'assigned',
      if (status.contains('invoice')) 'invoiceReviewStatus': status,
      if (status.contains('subscription')) 'subscriptionReviewStatus': status,
      if (status == 'business_close_review') 'closureReviewStatus': 'requested',
    };
  }
}

List<Map<String, dynamic>> adminSearch(
  List<Map<String, dynamic>> records,
  String query,
  List<String> fields,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return records;
  return records.where((record) {
    return fields.any(
        (field) => '${record[field] ?? ''}'.toLowerCase().contains(normalized));
  }).toList();
}

bool _isCompleted(Map<String, dynamic> item) {
  final status = '${item['status'] ?? ''}'.toLowerCase();
  return status.contains('complete') || status.contains('delivered');
}

bool _isFailed(Map<String, dynamic> item) {
  return '${item['status'] ?? ''}'.toLowerCase().contains('failed');
}

bool _isCancelled(Map<String, dynamic> item) {
  return '${item['status'] ?? ''}'.toLowerCase().contains('cancel');
}

bool _isResolved(Map<String, dynamic> item) {
  final status = '${item['status'] ?? ''}'.toLowerCase();
  return status.contains('resolved') || status.contains('closed');
}

bool _isInactive(Map<String, dynamic> item) {
  final status =
      '${item['status'] ?? item['accountStatus'] ?? ''}'.toLowerCase();
  return status.contains('inactive') || status.contains('deactivated');
}

bool _isActiveDriver(Map<String, dynamic> item) {
  final status =
      '${item['status'] ?? item['driverStatus'] ?? ''}'.toLowerCase();
  return status.contains('active') ||
      status.contains('online') ||
      status.contains('excellent') ||
      status.contains('good');
}

bool _isPendingDriver(Map<String, dynamic> item) {
  final status =
      '${item['verificationStatus'] ?? item['driverStatus'] ?? item['status'] ?? ''}'
          .toLowerCase();
  return status.contains('pending') || status.contains('review');
}

double _sumSince(List<Map<String, dynamic>> records, DateTime since) {
  return records.where((record) {
    final date = _dateValue(record['createdAt'] ?? record['timestamp']);
    return date == null || !date.isBefore(since);
  }).fold<double>(0, (total, item) => total + _moneyValue(item));
}

double _moneyValue(Map<String, dynamic> item) {
  return _number(
      item['amount'] ?? item['price'] ?? item['quote'] ?? item['total']);
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

DateTime? _dateValue(dynamic value) {
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

DateTime _dayStart(DateTime date) => DateTime(date.year, date.month, date.day);

double _rate(int count, int total) =>
    total == 0 ? 0 : _round2((count / total) * 100);

double _round2(double value) => (value * 100).roundToDouble() / 100;
