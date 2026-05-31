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
  viewDeliveries,
  editDeliveries,
  duplicateDeliveries,
  viewFinance,
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
      AdminPermission.viewHealthPlus,
      AdminPermission.viewAudit,
    ],
    AdminRole.driverManager: [
      AdminPermission.viewDashboard,
      AdminPermission.viewDrivers,
      AdminPermission.editDrivers,
      AdminPermission.approveDrivers,
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
  static Map<String, dynamic> statusPatch({
    required String status,
    String? assignedDriverId,
    required Object updatedAt,
  }) {
    return {
      'status': status,
      if (assignedDriverId != null && assignedDriverId.trim().isNotEmpty)
        'assignedDriverId': assignedDriverId.trim(),
      'adminUpdatedAt': updatedAt,
      'updatedAt': updatedAt,
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
