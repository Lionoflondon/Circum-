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

@immutable
class SenderBookingDraft {
  final SenderBookingStep step;
  final String pickupAddress;
  final String dropoffAddress;
  final String receiverName;
  final String receiverPhone;
  final String deliveryNotes;
  final String deliveryTime;
  final String itemName;
  final String itemDescription;
  final String weightLabel;
  final bool fragile;
  final bool highValue;
  final String irisConfidence;
  final String irisVehicle;
  final String selectedOption;
  final bool vanguard;
  final SenderPaymentStatus paymentStatus;
  final bool bookingConfirmed;

  const SenderBookingDraft({
    this.step = SenderBookingStep.pickup,
    this.pickupAddress = '',
    this.dropoffAddress = '',
    this.receiverName = '',
    this.receiverPhone = '',
    this.deliveryNotes = '',
    this.deliveryTime = 'Deliver now',
    this.itemName = '',
    this.itemDescription = '',
    this.weightLabel = '',
    this.fragile = false,
    this.highValue = false,
    this.irisConfidence = 'Medium',
    this.irisVehicle = 'Bike',
    this.selectedOption = 'Standard',
    this.vanguard = false,
    this.paymentStatus = SenderPaymentStatus.notReady,
    this.bookingConfirmed = false,
  });

  bool get canContinue {
    switch (step) {
      case SenderBookingStep.pickup:
        return pickupAddress.trim().isNotEmpty;
      case SenderBookingStep.dropoff:
        return dropoffAddress.trim().isNotEmpty;
      case SenderBookingStep.recipient:
        return receiverName.trim().isNotEmpty &&
            receiverPhone.trim().isNotEmpty;
      case SenderBookingStep.deliveryTime:
        return deliveryTime == 'Deliver now';
      case SenderBookingStep.parcel:
        return itemName.trim().isNotEmpty;
      case SenderBookingStep.iris:
      case SenderBookingStep.options:
      case SenderBookingStep.review:
        return true;
      case SenderBookingStep.payment:
        return paymentStatus == SenderPaymentStatus.ready;
      case SenderBookingStep.findingRider:
        return bookingConfirmed;
      case SenderBookingStep.liveTracking:
        return false;
    }
  }

  bool get exposesPaymentSuccess =>
      paymentStatus == SenderPaymentStatus.paid && bookingConfirmed;

  double get progress =>
      (SenderBookingStep.values.indexOf(step) + 1) /
      SenderBookingStep.values.length;

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
    String? dropoffAddress,
    String? receiverName,
    String? receiverPhone,
    String? deliveryNotes,
    String? deliveryTime,
    String? itemName,
    String? itemDescription,
    String? weightLabel,
    bool? fragile,
    bool? highValue,
    String? irisConfidence,
    String? irisVehicle,
    String? selectedOption,
    bool? vanguard,
    SenderPaymentStatus? paymentStatus,
    bool? bookingConfirmed,
  }) {
    return SenderBookingDraft(
      step: step ?? this.step,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      dropoffAddress: dropoffAddress ?? this.dropoffAddress,
      receiverName: receiverName ?? this.receiverName,
      receiverPhone: receiverPhone ?? this.receiverPhone,
      deliveryNotes: deliveryNotes ?? this.deliveryNotes,
      deliveryTime: deliveryTime ?? this.deliveryTime,
      itemName: itemName ?? this.itemName,
      itemDescription: itemDescription ?? this.itemDescription,
      weightLabel: weightLabel ?? this.weightLabel,
      fragile: fragile ?? this.fragile,
      highValue: highValue ?? this.highValue,
      irisConfidence: irisConfidence ?? this.irisConfidence,
      irisVehicle: irisVehicle ?? this.irisVehicle,
      selectedOption: selectedOption ?? this.selectedOption,
      vanguard: vanguard ?? this.vanguard,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      bookingConfirmed: bookingConfirmed ?? this.bookingConfirmed,
    );
  }
}

String senderStepTitle(SenderBookingStep step) {
  switch (step) {
    case SenderBookingStep.pickup:
      return 'Where are we collecting from?';
    case SenderBookingStep.dropoff:
      return 'Where is this going?';
    case SenderBookingStep.recipient:
      return "Who's receiving this parcel?";
    case SenderBookingStep.deliveryTime:
      return 'When should it arrive?';
    case SenderBookingStep.parcel:
      return 'Tell us about your parcel.';
    case SenderBookingStep.iris:
      return 'IRIS has checked the parcel.';
    case SenderBookingStep.options:
      return 'Choose your delivery options.';
    case SenderBookingStep.review:
      return 'Review your delivery.';
    case SenderBookingStep.payment:
      return 'Pay securely.';
    case SenderBookingStep.findingRider:
      return 'Finding the best rider for you...';
    case SenderBookingStep.liveTracking:
      return 'Track your delivery.';
  }
}

String mapConfidenceLabel(double score) {
  if (score >= .8) return 'High';
  if (score >= .55) return 'Medium';
  return 'Low';
}
