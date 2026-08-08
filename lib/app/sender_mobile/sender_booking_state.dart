import 'package:flutter/foundation.dart';

enum SenderBookingStep {
  pickup,
  dropoff,
  recipient,
  deliveryTime,
  parcel,
  iris,
  options,
  review,
  payment,
  findingRider,
  liveTracking,
}

enum SenderPaymentStatus { notReady, ready, processing, paid, failed }

enum SenderDeliveryTimingType { now, scheduled }

enum SenderFallbackPaymentMethod { card, applePay, googlePay }

const senderDeliverySpeeds = ['Standard', 'Express'];
const senderVanguardAddOnPriceGbp = 1.99;
const senderVanguardProtocolLabel = 'Vanguard Delivery Protocol';
const senderRothPoundValue = 1.0;

bool isSenderDeliverySpeed(String value) =>
    senderDeliverySpeeds.contains(value);

String senderPaymentMethodLabel(SenderFallbackPaymentMethod method) {
  switch (method) {
    case SenderFallbackPaymentMethod.card:
      return 'Card';
    case SenderFallbackPaymentMethod.applePay:
      return 'Apple Pay';
    case SenderFallbackPaymentMethod.googlePay:
      return 'Google Pay';
  }
}

String senderFallbackPaymentMethodPrompt() => 'Saved card';

bool isSenderScheduledDateValid(String value, {DateTime? now}) {
  final parsed = DateTime.tryParse(value.trim());
  if (parsed == null) return false;
  final today = now ?? DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);
  final parsedOnly = DateTime(parsed.year, parsed.month, parsed.day);
  return !parsedOnly.isBefore(todayOnly);
}

List<DateTime> senderScheduleDateOptions({DateTime? now, int days = 7}) {
  final base = now ?? DateTime.now();
  final today = DateTime(base.year, base.month, base.day);
  return List<DateTime>.generate(
      days, (index) => today.add(Duration(days: index)));
}

String senderScheduleDateValue(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String senderScheduleDayLabel(DateTime date, {DateTime? now}) {
  final base = now ?? DateTime.now();
  final today = DateTime(base.year, base.month, base.day);
  final dateOnly = DateTime(date.year, date.month, date.day);
  if (dateOnly == today) return 'Today';
  if (dateOnly == today.add(const Duration(days: 1))) return 'Tomorrow';
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return weekdays[date.weekday - 1];
}

String senderScheduleMonthDayLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]}';
}

bool isSenderCustomWindowValid(String start, String end) {
  final pattern = RegExp(r'^\d{2}:\d{2}$');
  if (!pattern.hasMatch(start.trim()) || !pattern.hasMatch(end.trim())) {
    return false;
  }
  final startParts = start.split(':').map(int.tryParse).toList();
  final endParts = end.split(':').map(int.tryParse).toList();
  if (startParts.any((part) => part == null) ||
      endParts.any((part) => part == null)) {
    return false;
  }
  final startMinutes = startParts[0]! * 60 + startParts[1]!;
  final endMinutes = endParts[0]! * 60 + endParts[1]!;
  return startParts[0]! < 24 &&
      startParts[1]! < 60 &&
      endParts[0]! < 24 &&
      endParts[1]! < 60 &&
      endMinutes > startMinutes;
}

@immutable
class SenderPaymentSplit {
  final double totalDue;
  final bool rothEnabled;
  final double availableRothCredits;
  final double rothAppliedCredits;
  final double rothAppliedAmount;
  final double remainingAmount;
  final SenderFallbackPaymentMethod? fallbackMethod;

  const SenderPaymentSplit({
    required this.totalDue,
    required this.rothEnabled,
    required this.availableRothCredits,
    required this.rothAppliedCredits,
    required this.rothAppliedAmount,
    required this.remainingAmount,
    required this.fallbackMethod,
  });

  bool get fullyCoveredByRoth =>
      rothEnabled && remainingAmount <= 0 && rothAppliedAmount > 0;

  bool get requiresFallback => remainingAmount > 0;

  bool get canSubmit => !requiresFallback || fallbackMethod != null;

  String get splitSummary {
    if (!rothEnabled || rothAppliedAmount <= 0) {
      final method = fallbackMethod == null
          ? senderFallbackPaymentMethodPrompt()
          : senderPaymentMethodLabel(fallbackMethod!);
      return '$method (${formatSenderCurrency(remainingAmount)})';
    }
    final rothPart =
        '${formatSenderRothCredits(rothAppliedCredits)} Roth (${formatSenderCurrency(rothAppliedAmount)})';
    if (remainingAmount <= 0) return rothPart;
    final method = fallbackMethod == null
        ? senderFallbackPaymentMethodPrompt()
        : senderPaymentMethodLabel(fallbackMethod!);
    return '$rothPart + $method (${formatSenderCurrency(remainingAmount)})';
  }

  String get ctaLabel {
    if (!canSubmit) return 'Choose payment method';
    if (fullyCoveredByRoth) {
      return 'Pay ${formatSenderCurrency(totalDue)} with Roth';
    }
    final method = senderPaymentMethodLabel(fallbackMethod!);
    if (rothEnabled && rothAppliedAmount > 0) {
      return 'Pay ${formatSenderCurrency(remainingAmount)} with $method + ${formatSenderRothCredits(rothAppliedCredits)} Roth';
    }
    return 'Pay ${formatSenderCurrency(remainingAmount)} with $method';
  }

  static SenderPaymentSplit calculate({
    required double totalDue,
    required bool rothEnabled,
    required double availableRothCredits,
    SenderFallbackPaymentMethod? fallbackMethod,
  }) {
    final maxRothAmount = availableRothCredits * senderRothPoundValue;
    final rothAppliedAmount =
        rothEnabled ? maxRothAmount.clamp(0, totalDue).toDouble() : 0.0;
    final rothAppliedCredits = rothAppliedAmount / senderRothPoundValue;
    final remaining = (totalDue - rothAppliedAmount).clamp(0, totalDue);
    return SenderPaymentSplit(
      totalDue: totalDue,
      rothEnabled: rothEnabled,
      availableRothCredits: availableRothCredits,
      rothAppliedCredits: rothAppliedCredits,
      rothAppliedAmount: rothAppliedAmount,
      remainingAmount: remaining.toDouble(),
      fallbackMethod: remaining > 0 ? fallbackMethod : null,
    );
  }
}

String formatSenderCurrency(double value) => '£${value.toStringAsFixed(2)}';

String formatSenderRothCredits(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
}

@immutable
class SenderBookingDraft {
  final SenderBookingStep step;
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final String dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;
  final String receiverName;
  final String receiverPhone;
  final String deliveryNotes;
  final SenderDeliveryTimingType deliveryTimingType;
  final String scheduledDate;
  final String scheduledWindow;
  final String customWindowStart;
  final String customWindowEnd;
  final String itemName;
  final String itemDescription;
  final String weightLabel;
  final bool fragile;
  final bool highValue;
  final String irisConfidence;
  final String irisVehicle;
  final String selectedVehicle;
  final String selectedOption;
  final bool vanguard;
  final SenderPaymentStatus paymentStatus;
  final bool bookingConfirmed;
  final SenderFallbackPaymentMethod? selectedPaymentMethod;
  final String selectedPaymentMethodId;
  final String selectedPaymentMethodLabel;
  final bool rothEnabled;
  final double? rothAvailableCredits;
  final double rothAppliedAmount;
  final double rothAppliedCredits;
  final double remainingAmount;
  final String paymentSplitSummary;
  final double? amountDue;
  final bool cardConfirmationStarted;

  const SenderBookingDraft({
    this.step = SenderBookingStep.pickup,
    this.pickupAddress = '',
    this.pickupLat,
    this.pickupLng,
    this.dropoffAddress = '',
    this.dropoffLat,
    this.dropoffLng,
    this.receiverName = '',
    this.receiverPhone = '',
    this.deliveryNotes = '',
    this.deliveryTimingType = SenderDeliveryTimingType.now,
    this.scheduledDate = '',
    this.scheduledWindow = '',
    this.customWindowStart = '',
    this.customWindowEnd = '',
    this.itemName = '',
    this.itemDescription = '',
    this.weightLabel = '',
    this.fragile = false,
    this.highValue = false,
    this.irisConfidence = 'Medium',
    this.irisVehicle = 'Motorbike',
    this.selectedVehicle = '',
    this.selectedOption = 'Standard',
    this.vanguard = false,
    this.paymentStatus = SenderPaymentStatus.notReady,
    this.bookingConfirmed = false,
    this.selectedPaymentMethod,
    this.selectedPaymentMethodId = '',
    this.selectedPaymentMethodLabel = '',
    this.rothEnabled = false,
    this.rothAvailableCredits,
    this.rothAppliedAmount = 0,
    this.rothAppliedCredits = 0,
    this.remainingAmount = 0,
    this.paymentSplitSummary = '',
    this.amountDue,
    this.cardConfirmationStarted = false,
  });

  bool get canContinue {
    switch (step) {
      case SenderBookingStep.pickup:
        return isSenderCanonicalCoordinateUsable(pickupLat, pickupLng) ||
            isSenderTypedAddressSpecific(pickupAddress);
      case SenderBookingStep.dropoff:
        return isSenderCanonicalCoordinateUsable(dropoffLat, dropoffLng) ||
            isSenderTypedAddressSpecific(dropoffAddress);
      case SenderBookingStep.recipient:
        return receiverName.trim().isNotEmpty &&
            receiverPhone.trim().isNotEmpty;
      case SenderBookingStep.deliveryTime:
        return isDeliveryTimeValid;
      case SenderBookingStep.parcel:
        return itemName.trim().isNotEmpty;
      case SenderBookingStep.iris:
      case SenderBookingStep.options:
      case SenderBookingStep.review:
        return true;
      case SenderBookingStep.payment:
        return paymentStatus == SenderPaymentStatus.paid;
      case SenderBookingStep.findingRider:
        return bookingConfirmed;
      case SenderBookingStep.liveTracking:
        return false;
    }
  }

  bool get exposesPaymentSuccess =>
      paymentStatus == SenderPaymentStatus.paid && bookingConfirmed;

  double get addOnTotalGbp => vanguard ? senderVanguardAddOnPriceGbp : 0;

  double? totalWithAddOns(double? deliveryPrice) =>
      deliveryPrice == null ? null : deliveryPrice + addOnTotalGbp;

  bool get vanguardProtocolEnabled => vanguard;

  String get vanguardStatus =>
      vanguardProtocolEnabled ? 'pickup_verification_pending' : 'not_required';

  double get progress =>
      (SenderBookingStep.values.indexOf(step) + 1) /
      SenderBookingStep.values.length;

  bool get isDeliveryTimeValid {
    if (deliveryTimingType == SenderDeliveryTimingType.now) return true;
    if (!isSenderScheduledDateValid(scheduledDate)) return false;
    if (scheduledWindow.trim().isEmpty) return false;
    if (scheduledWindow == 'Custom') {
      return isSenderCustomWindowValid(customWindowStart, customWindowEnd);
    }
    return true;
  }

  String get deliveryTimeSummary {
    if (deliveryTimingType == SenderDeliveryTimingType.now) {
      return 'Deliver now';
    }
    if (scheduledDate.trim().isEmpty || scheduledWindow.trim().isEmpty) {
      return 'Scheduled';
    }
    final window = scheduledWindow == 'Custom'
        ? '$customWindowStart-$customWindowEnd'
        : scheduledWindow;
    return 'Scheduled: $scheduledDate, $window';
  }

  SenderBookingDraft next() {
    if (!canContinue) return this;
    if (step == SenderBookingStep.payment &&
        paymentStatus != SenderPaymentStatus.paid) {
      return this;
    }
    final index = SenderBookingStep.values.indexOf(step);
    if (index >= SenderBookingStep.values.length - 1) return this;
    return copyWith(step: SenderBookingStep.values[index + 1]);
  }

  SenderBookingDraft back() {
    final index = SenderBookingStep.values.indexOf(step);
    if (index <= 0) return this;
    return copyWith(step: SenderBookingStep.values[index - 1]);
  }

  SenderBookingDraft copyWith({
    SenderBookingStep? step,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    bool clearPickupCoordinate = false,
    String? dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    bool clearDropoffCoordinate = false,
    String? receiverName,
    String? receiverPhone,
    String? deliveryNotes,
    SenderDeliveryTimingType? deliveryTimingType,
    String? scheduledDate,
    String? scheduledWindow,
    String? customWindowStart,
    String? customWindowEnd,
    String? itemName,
    String? itemDescription,
    String? weightLabel,
    bool? fragile,
    bool? highValue,
    String? irisConfidence,
    String? irisVehicle,
    String? selectedVehicle,
    String? selectedOption,
    bool? vanguard,
    SenderPaymentStatus? paymentStatus,
    bool? bookingConfirmed,
    SenderFallbackPaymentMethod? selectedPaymentMethod,
    String? selectedPaymentMethodId,
    String? selectedPaymentMethodLabel,
    bool clearSelectedPaymentMethod = false,
    bool? rothEnabled,
    double? rothAvailableCredits,
    bool clearRothAvailableCredits = false,
    double? rothAppliedAmount,
    double? rothAppliedCredits,
    double? remainingAmount,
    String? paymentSplitSummary,
    double? amountDue,
    bool clearAmountDue = false,
    bool? cardConfirmationStarted,
  }) {
    return SenderBookingDraft(
      step: step ?? this.step,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupLat: clearPickupCoordinate ? null : pickupLat ?? this.pickupLat,
      pickupLng: clearPickupCoordinate ? null : pickupLng ?? this.pickupLng,
      dropoffAddress: dropoffAddress ?? this.dropoffAddress,
      dropoffLat: clearDropoffCoordinate ? null : dropoffLat ?? this.dropoffLat,
      dropoffLng: clearDropoffCoordinate ? null : dropoffLng ?? this.dropoffLng,
      receiverName: receiverName ?? this.receiverName,
      receiverPhone: receiverPhone ?? this.receiverPhone,
      deliveryNotes: deliveryNotes ?? this.deliveryNotes,
      deliveryTimingType: deliveryTimingType ?? this.deliveryTimingType,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      scheduledWindow: scheduledWindow ?? this.scheduledWindow,
      customWindowStart: customWindowStart ?? this.customWindowStart,
      customWindowEnd: customWindowEnd ?? this.customWindowEnd,
      itemName: itemName ?? this.itemName,
      itemDescription: itemDescription ?? this.itemDescription,
      weightLabel: weightLabel ?? this.weightLabel,
      fragile: fragile ?? this.fragile,
      highValue: highValue ?? this.highValue,
      irisConfidence: irisConfidence ?? this.irisConfidence,
      irisVehicle: irisVehicle ?? this.irisVehicle,
      selectedVehicle: selectedVehicle ?? this.selectedVehicle,
      selectedOption: selectedOption ?? this.selectedOption,
      vanguard: vanguard ?? this.vanguard,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      bookingConfirmed: bookingConfirmed ?? this.bookingConfirmed,
      selectedPaymentMethod: clearSelectedPaymentMethod
          ? null
          : selectedPaymentMethod ?? this.selectedPaymentMethod,
      selectedPaymentMethodId: clearSelectedPaymentMethod
          ? ''
          : selectedPaymentMethodId ?? this.selectedPaymentMethodId,
      selectedPaymentMethodLabel: clearSelectedPaymentMethod
          ? ''
          : selectedPaymentMethodLabel ?? this.selectedPaymentMethodLabel,
      rothEnabled: rothEnabled ?? this.rothEnabled,
      rothAvailableCredits: clearRothAvailableCredits
          ? null
          : rothAvailableCredits ?? this.rothAvailableCredits,
      rothAppliedAmount: rothAppliedAmount ?? this.rothAppliedAmount,
      rothAppliedCredits: rothAppliedCredits ?? this.rothAppliedCredits,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      paymentSplitSummary: paymentSplitSummary ?? this.paymentSplitSummary,
      amountDue: clearAmountDue ? null : amountDue ?? this.amountDue,
      cardConfirmationStarted:
          cardConfirmationStarted ?? this.cardConfirmationStarted,
    );
  }

  Map<String, dynamic> toBackendDraftPayload() => {
        'version': 1,
        'step': step.name,
        'status': 'draft',
        'completed': false,
        'pickup': {
          'address': pickupAddress,
          if (pickupLat != null && pickupLng != null)
            'coordinate': {
              'lat': pickupLat,
              'lng': pickupLng,
            },
        },
        'dropoff': {
          'address': dropoffAddress,
          if (dropoffLat != null && dropoffLng != null)
            'coordinate': {
              'lat': dropoffLat,
              'lng': dropoffLng,
            },
        },
        'recipient': {
          'name': receiverName,
          'phone': receiverPhone,
          'deliveryNotes': deliveryNotes,
        },
        'deliveryTime': {
          'type': deliveryTimingType == SenderDeliveryTimingType.now
              ? 'now'
              : 'scheduled',
          'scheduledDate': scheduledDate,
          'scheduledWindow': scheduledWindow,
          'customWindowStart': customWindowStart,
          'customWindowEnd': customWindowEnd,
          'summary': deliveryTimeSummary,
        },
        'parcel': {
          'itemName': itemName,
          'description': itemDescription,
          'weightLabel': weightLabel,
          'fragile': fragile,
          'highValue': highValue,
        },
        'iris': {
          'confidence': irisConfidence,
          'recommendedVehicle': irisVehicle,
          'selectedVehicle': selectedVehicle,
        },
        'deliveryOptions': {
          'selectedOption': selectedOption,
          'vanguard': vanguard,
        },
        'review': {
          'amountDue': amountDue,
        },
        'paymentMethod': {
          'type': selectedPaymentMethod?.name ?? '',
          'paymentMethodId': selectedPaymentMethodId,
          'label': selectedPaymentMethodLabel,
          'rothEnabled': rothEnabled,
        },
      };

  factory SenderBookingDraft.fromBackendDraft(Map<String, dynamic> data) {
    final pickup = _draftMap(data['pickup']);
    final dropoff = _draftMap(data['dropoff']);
    final pickupCoordinate = _draftMap(pickup['coordinate']);
    final dropoffCoordinate = _draftMap(dropoff['coordinate']);
    final recipient = _draftMap(data['recipient']);
    final deliveryTime = _draftMap(data['deliveryTime']);
    final parcel = _draftMap(data['parcel']);
    final iris = _draftMap(data['iris']);
    final deliveryOptions = _draftMap(data['deliveryOptions']);
    final review = _draftMap(data['review']);
    final paymentMethod = _draftMap(data['paymentMethod']);
    final restoredStep = SenderBookingStep.values.firstWhere(
      (value) => value.name == '${data['step'] ?? ''}',
      orElse: () => SenderBookingStep.pickup,
    );
    final timingType = '${deliveryTime['type'] ?? ''}' == 'scheduled'
        ? SenderDeliveryTimingType.scheduled
        : SenderDeliveryTimingType.now;
    final matchingMethods = SenderFallbackPaymentMethod.values.where(
      (value) => value.name == '${paymentMethod['type'] ?? ''}',
    );
    final fallback = matchingMethods.isEmpty ? null : matchingMethods.first;

    return SenderBookingDraft(
      step: restoredStep == SenderBookingStep.findingRider ||
              restoredStep == SenderBookingStep.liveTracking
          ? SenderBookingStep.pickup
          : restoredStep,
      pickupAddress: '${pickup['address'] ?? ''}',
      pickupLat: _draftDouble(pickupCoordinate['lat']),
      pickupLng: _draftDouble(pickupCoordinate['lng']),
      dropoffAddress: '${dropoff['address'] ?? ''}',
      dropoffLat: _draftDouble(dropoffCoordinate['lat']),
      dropoffLng: _draftDouble(dropoffCoordinate['lng']),
      receiverName: '${recipient['name'] ?? ''}',
      receiverPhone: '${recipient['phone'] ?? ''}',
      deliveryNotes: '${recipient['deliveryNotes'] ?? ''}',
      deliveryTimingType: timingType,
      scheduledDate: '${deliveryTime['scheduledDate'] ?? ''}',
      scheduledWindow: '${deliveryTime['scheduledWindow'] ?? ''}',
      customWindowStart: '${deliveryTime['customWindowStart'] ?? ''}',
      customWindowEnd: '${deliveryTime['customWindowEnd'] ?? ''}',
      itemName: '${parcel['itemName'] ?? ''}',
      itemDescription: '${parcel['description'] ?? ''}',
      weightLabel: '${parcel['weightLabel'] ?? ''}',
      fragile: parcel['fragile'] == true,
      highValue: parcel['highValue'] == true,
      irisConfidence: '${iris['confidence'] ?? 'Medium'}',
      irisVehicle: '${iris['recommendedVehicle'] ?? 'Motorbike'}',
      selectedVehicle: '${iris['selectedVehicle'] ?? ''}',
      selectedOption: '${deliveryOptions['selectedOption'] ?? 'Standard'}',
      vanguard: deliveryOptions['vanguard'] == true,
      selectedPaymentMethod: fallback,
      selectedPaymentMethodId: '${paymentMethod['paymentMethodId'] ?? ''}',
      selectedPaymentMethodLabel: '${paymentMethod['label'] ?? ''}',
      rothEnabled: paymentMethod['rothEnabled'] == true,
      amountDue: _draftDouble(review['amountDue']),
    );
  }
}

Map<String, dynamic> _draftMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

double? _draftDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

bool isSenderTypedAddressSpecific(String value) {
  final text = value.trim();
  if (text.length < 8) return false;
  final hasDigit = RegExp(r'\d').hasMatch(text);
  final hasSeparator =
      text.contains(',') || text.split(RegExp(r'\s+')).length >= 3;
  return hasDigit && hasSeparator;
}

bool isSenderCanonicalCoordinateUsable(double? latitude, double? longitude) {
  if (latitude == null || longitude == null) return false;
  if (!latitude.isFinite || !longitude.isFinite) return false;
  return latitude != 0 || longitude != 0;
}

String senderStepTitle(SenderBookingStep step) {
  switch (step) {
    case SenderBookingStep.pickup:
      return 'Where are we collecting from?';
    case SenderBookingStep.dropoff:
      return 'Where is this going?';
    case SenderBookingStep.recipient:
      return "Who's receiving\nthis parcel?";
    case SenderBookingStep.deliveryTime:
      return 'Delivery time';
    case SenderBookingStep.parcel:
      return 'Tell us about your parcel.';
    case SenderBookingStep.iris:
      return 'IRIS has estimated your parcel.';
    case SenderBookingStep.options:
      return 'Choose your delivery options.';
    case SenderBookingStep.review:
      return 'Review your delivery.';
    case SenderBookingStep.payment:
      return 'Payment';
    case SenderBookingStep.findingRider:
      return 'Finding the best Circum Rider for you...';
    case SenderBookingStep.liveTracking:
      return 'Track your delivery.';
  }
}

String mapConfidenceLabel(double score) {
  if (score >= .8) return 'High';
  if (score >= .55) return 'Medium';
  return 'Low';
}

int senderQuantityFromItemName(String value) {
  final text = value.trim();
  if (text.isEmpty) return 1;
  final leading = RegExp(r'^(\d{1,3})\s+').firstMatch(text);
  if (leading != null) return int.tryParse(leading.group(1)!) ?? 1;
  final trailing = RegExp(
    r'(?:x|×)\s*(\d{1,3})$',
    caseSensitive: false,
  ).firstMatch(text);
  if (trailing != null) return int.tryParse(trailing.group(1)!) ?? 1;
  return 1;
}
