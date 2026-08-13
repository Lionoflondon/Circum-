import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

enum BusinessSection {
  overview,
  deliveries,
  invoices,
  team,
  healthPlus,
  gifts,
  vanguard,
  analytics,
  finance,
  settings,
}

enum BusinessDeliverySegment { active, scheduled, completed }

class BusinessAccount {
  final String id;
  final String name;
  final String status;
  final String contactName;
  final String contactEmail;
  final String phone;
  final String billingEmail;
  final String businessAddress;
  final Map<String, dynamic>? businessAddressCanonical;
  final String companyNumber;
  final String companyCode;
  final String defaultPickupAddress;
  final List<Map<String, dynamic>> teamMembers;
  final List<String> connectedProducts;
  final Map<String, dynamic> notificationPreferences;
  final Map<String, dynamic> paymentPreferences;
  final List<Map<String, dynamic>> irisMoments;
  final bool isPatron;
  final int? patronNumber;

  const BusinessAccount({
    required this.id,
    required this.name,
    required this.status,
    required this.contactName,
    required this.contactEmail,
    required this.phone,
    required this.billingEmail,
    required this.businessAddress,
    this.businessAddressCanonical,
    required this.companyNumber,
    required this.companyCode,
    required this.defaultPickupAddress,
    required this.teamMembers,
    required this.connectedProducts,
    required this.notificationPreferences,
    required this.paymentPreferences,
    this.irisMoments = const [],
    this.isPatron = false,
    this.patronNumber,
  });

  factory BusinessAccount.fromMap(String id, Map<String, dynamic> data) {
    final recognitions = Map<String, dynamic>.from(
      data['recognitions'] as Map? ?? {},
    );
    final patron = Map<String, dynamic>.from(
      recognitions['patron'] as Map? ?? {},
    );
    final pickups = (data['defaultPickupAddresses'] as List? ?? const [])
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return BusinessAccount(
      id: id,
      name: '${data['businessName'] ?? 'Business'}'.trim(),
      status:
          '${data['approvalStatus'] ?? data['status'] ?? data['businessStatus'] ?? 'pending'}'
              .trim()
              .toLowerCase(),
      contactName: '${data['contactName'] ?? ''}'.trim(),
      contactEmail: '${data['contactEmail'] ?? ''}'.trim(),
      phone: '${data['phone'] ?? ''}'.trim(),
      billingEmail: '${data['billingEmail'] ?? ''}'.trim(),
      businessAddress: '${data['businessAddress'] ?? ''}'.trim(),
      businessAddressCanonical: data['businessAddressCanonical'] is Map
          ? Map<String, dynamic>.from(data['businessAddressCanonical'] as Map)
          : null,
      companyNumber: '${data['companyNumber'] ?? ''}'.trim(),
      companyCode: '${data['companyCode'] ?? ''}'.trim(),
      defaultPickupAddress: pickups.isEmpty ? '' : pickups.first,
      teamMembers: (data['teamMembers'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
      connectedProducts: (data['connectedProducts'] as List? ?? const [])
          .map((item) => '$item'.trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      notificationPreferences: Map<String, dynamic>.from(
        data['notificationPreferences'] as Map? ?? const {},
      ),
      paymentPreferences: Map<String, dynamic>.from(
        data['paymentPreferences'] as Map? ?? const {},
      ),
      irisMoments: ((data['irisMoments'] ??
                  data['moments'] ??
                  data['businessMoments']) as List? ??
              const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
      isPatron: patron['awarded'] == true || data['isPatron'] == true,
      patronNumber: (patron['number'] as num?)?.toInt() ??
          (data['patronNumber'] as num?)?.toInt(),
    );
  }

  bool get isApproved => status == 'approved' || status == 'verified';
  String get statusLabel =>
      isApproved ? 'Verified Business' : 'Pending Approval';
}

class BusinessCreateDraft {
  final String companyName;
  final String businessType;
  final String businessEmail;
  final String businessPhone;
  final String businessAddress;
  final Map<String, dynamic>? businessAddressCanonical;
  final String vatNumber;
  final String businessSize;
  final bool acceptTerms;

  const BusinessCreateDraft({
    required this.companyName,
    required this.businessType,
    required this.businessEmail,
    required this.businessPhone,
    required this.businessAddress,
    this.businessAddressCanonical,
    required this.vatNumber,
    required this.businessSize,
    required this.acceptTerms,
  });
}

class BusinessCreatedResult {
  final String businessId;
  final String companyName;
  final String companyCode;

  const BusinessCreatedResult({
    required this.businessId,
    required this.companyName,
    required this.companyCode,
  });

  factory BusinessCreatedResult.fromMap(Map<String, dynamic> data) =>
      BusinessCreatedResult(
        businessId: '${data['businessId'] ?? ''}',
        companyName: '${data['companyName'] ?? 'Business'}',
        companyCode: '${data['companyCode'] ?? ''}',
      );
}

class BusinessCodeLookupResult {
  final String businessId;
  final String companyName;
  final String businessLogo;
  final String businessAddress;
  final String businessStatus;
  final String joinPolicy;
  final String roleRequested;

  const BusinessCodeLookupResult({
    required this.businessId,
    required this.companyName,
    required this.businessLogo,
    required this.businessAddress,
    required this.businessStatus,
    required this.joinPolicy,
    required this.roleRequested,
  });

  factory BusinessCodeLookupResult.fromMap(Map<String, dynamic> data) =>
      BusinessCodeLookupResult(
        businessId: '${data['businessId'] ?? ''}',
        companyName: '${data['companyName'] ?? 'Business'}',
        businessLogo: '${data['businessLogo'] ?? ''}',
        businessAddress: '${data['businessAddress'] ?? ''}',
        businessStatus: '${data['businessStatus'] ?? 'pending'}',
        joinPolicy: '${data['joinPolicy'] ?? 'approval_required'}',
        roleRequested: '${data['roleRequested'] ?? 'member'}',
      );
}

class BusinessAccessRequest {
  final String id;
  final String businessId;
  final String name;
  final String email;
  final String roleRequested;
  final String status;
  final DateTime? createdAt;

  const BusinessAccessRequest({
    required this.id,
    required this.businessId,
    required this.name,
    required this.email,
    required this.roleRequested,
    required this.status,
    this.createdAt,
  });

  factory BusinessAccessRequest.fromMap(String id, Map<String, dynamic> data) =>
      BusinessAccessRequest(
        id: id,
        businessId: '${data['businessId'] ?? ''}',
        name: '${data['name'] ?? 'Applicant'}',
        email: '${data['email'] ?? ''}',
        roleRequested: '${data['roleRequested'] ?? 'member'}',
        status: '${data['status'] ?? 'pending'}'.toLowerCase(),
        createdAt: _date(data['createdAt']),
      );
}

class BusinessDelivery {
  final String id;
  final String pickup;
  final String dropoff;
  final String status;
  final String bookedBy;
  final String vehicle;
  final String category;
  final double amount;
  final DateTime? createdAt;
  final DateTime? scheduledAt;
  final Duration? duration;

  const BusinessDelivery({
    required this.id,
    required this.pickup,
    required this.dropoff,
    required this.status,
    required this.bookedBy,
    required this.vehicle,
    required this.category,
    required this.amount,
    this.createdAt,
    this.scheduledAt,
    this.duration,
  });

  factory BusinessDelivery.fromMap(String id, Map<String, dynamic> data) {
    return BusinessDelivery(
      id: id,
      pickup: _addressLabel(data['pickupAddress'] ?? data['pickup']),
      dropoff: _addressLabel(
        data['dropoffAddress'] ?? data['dropOffAddress'] ?? data['dropoff'],
      ),
      status: '${data['deliveryStatus'] ?? data['status'] ?? 'draft'}'
          .trim()
          .toLowerCase(),
      bookedBy: '${data['bookedByName'] ?? data['senderName'] ?? ''}'.trim(),
      vehicle: '${data['vehicleType'] ?? data['vehicle'] ?? ''}'.trim(),
      category:
          '${data['category'] ?? data['itemCategory'] ?? 'Delivery'}'.trim(),
      amount: _money(
        data['totalAmount'] ?? data['price'] ?? data['amountPaid'],
      ),
      createdAt: _date(data['createdAt']),
      scheduledAt: _date(data['scheduledAt'] ?? data['preferredDeliveryDate']),
      duration: data['durationMinutes'] is num
          ? Duration(minutes: (data['durationMinutes'] as num).round())
          : null,
    );
  }

  bool get isCompleted => const {
        'delivered',
        'completed',
        'cancelled',
        'cancelled_admin',
      }.contains(status);

  bool get isScheduled =>
      !isCompleted &&
      const {
        'scheduled',
        'awaiting_payment',
        'payment_complete',
        'awaiting_broadcast',
      }.contains(status);

  bool get isActive => !isCompleted && !isScheduled;
  bool get hasVanguard => category.toLowerCase().contains('vanguard');
}

class BusinessInvoice {
  final String id;
  final String number;
  final String status;
  final double total;
  final double balanceDue;
  final double rothApplied;
  final int deliveryCount;
  final DateTime? dueAt;
  final DateTime? createdAt;
  final String paymentReference;

  const BusinessInvoice({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    required this.balanceDue,
    required this.rothApplied,
    required this.deliveryCount,
    required this.paymentReference,
    this.dueAt,
    this.createdAt,
  });

  factory BusinessInvoice.fromMap(String id, Map<String, dynamic> data) {
    return BusinessInvoice(
      id: id,
      number: '${data['invoiceNumber'] ?? id}'.trim(),
      status: '${data['status'] ?? 'draft'}'.trim().toLowerCase(),
      total: _money(data['total'] ?? data['subtotal']),
      balanceDue: _money(data['balanceDue'] ?? data['total']),
      rothApplied: _money(data['rothApplied'] ?? data['rothAmount']),
      deliveryCount: (data['deliveryCount'] as num?)?.toInt() ??
          (data['deliveryIds'] as List?)?.length ??
          0,
      dueAt: _date(data['dueAt'] ?? data['dueDate']),
      createdAt: _date(data['createdAt']),
      paymentReference:
          '${data['stripePaymentIntentId'] ?? data['paymentReference'] ?? ''}'
              .trim(),
    );
  }

  bool get isPaid => status == 'paid' || status == 'paid_manually';
}

class BusinessInvoicePaymentPlan {
  final double total;
  final double availableRoth;
  final double rothApplied;
  final double cardAmount;

  const BusinessInvoicePaymentPlan({
    required this.total,
    required this.availableRoth,
    required this.rothApplied,
    required this.cardAmount,
  });

  factory BusinessInvoicePaymentPlan.calculate({
    required double total,
    required double availableRoth,
    required bool applyRoth,
  }) {
    final safeTotal = total < 0 ? 0.0 : total;
    final safeBalance = availableRoth < 0 ? 0.0 : availableRoth;
    final applied = applyRoth ? math.min(safeTotal, safeBalance) : 0.0;
    return BusinessInvoicePaymentPlan(
      total: safeTotal,
      availableRoth: safeBalance,
      rothApplied: applied,
      cardAmount: math.max(0, safeTotal - applied),
    );
  }

  bool get isRothOnly => rothApplied > 0 && cardAmount == 0;
  bool get isSplit => rothApplied > 0 && cardAmount > 0;
}

class BusinessInvoicePaymentResult {
  final bool paid;
  final String method;
  final double totalInvoice;
  final double rothApplied;
  final double cardAmount;
  final Uri? checkoutUrl;

  const BusinessInvoicePaymentResult({
    required this.paid,
    required this.method,
    required this.totalInvoice,
    required this.rothApplied,
    required this.cardAmount,
    this.checkoutUrl,
  });
}

class BusinessRequestSummary {
  final String id;
  final String title;
  final String status;
  final DateTime? createdAt;

  const BusinessRequestSummary({
    required this.id,
    required this.title,
    required this.status,
    this.createdAt,
  });
}

class BusinessWalletSummary {
  final double rothBalance;
  final double lifetimeOffset;
  final String status;

  const BusinessWalletSummary({
    required this.rothBalance,
    required this.lifetimeOffset,
    required this.status,
  });

  static const empty = BusinessWalletSummary(
    rothBalance: 0,
    lifetimeOffset: 0,
    status: 'active',
  );
}

class BusinessWorkspaceData {
  final BusinessAccount account;
  final List<BusinessDelivery> deliveries;
  final List<BusinessInvoice> invoices;
  final List<BusinessRequestSummary> healthRequests;
  final List<BusinessRequestSummary> giftRequests;
  final BusinessWalletSummary wallet;

  const BusinessWorkspaceData({
    required this.account,
    required this.deliveries,
    required this.invoices,
    required this.healthRequests,
    required this.giftRequests,
    required this.wallet,
  });

  int get monthlyDeliveries {
    final now = DateTime.now();
    return deliveries.where((item) {
      final date = item.createdAt;
      return date != null && date.year == now.year && date.month == now.month;
    }).length;
  }

  double get outstandingBalance => invoices
      .where((item) => !item.isPaid)
      .fold<double>(0, (total, item) => total + item.balanceDue);

  int get activeHealthRequests => healthRequests
      .where((item) => !const {'completed', 'delivered'}.contains(item.status))
      .length;

  int get activeGiftRequests => giftRequests
      .where((item) => !const {'completed', 'delivered'}.contains(item.status))
      .length;
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

double _money(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

String _addressLabel(dynamic value) {
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    for (final key in const [
      'formattedAddress',
      'addressLine1',
      'address',
      'description',
    ]) {
      final text = '${map[key] ?? ''}'.trim();
      if (text.isNotEmpty && text != 'null' && text != 'undefined') return text;
    }
  }
  final text = '${value ?? ''}'.trim();
  return text == 'null' || text == 'undefined' ? '' : text;
}
