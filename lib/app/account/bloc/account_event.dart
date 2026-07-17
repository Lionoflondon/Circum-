part of 'account_bloc.dart';

abstract class AccountEvent extends Equatable {
  const AccountEvent();

  @override
  List<Object?> get props => [];
}

class PaymentStart extends AccountEvent {}

class PaymentCreateIntent extends AccountEvent {
  final BillingDetails? billingDetails;
  final int amount;
  final double? distanceMiles;
  final double? weightKg;
  final String? selectedSpeed;
  final String? paymentRequestId;
  final String? deliveryId;
  final bool saveCard;
  final String email;
  const PaymentCreateIntent(
      {this.billingDetails,
      required this.amount,
      required this.email,
      this.distanceMiles,
      this.weightKg,
      this.selectedSpeed,
      this.paymentRequestId,
      this.deliveryId,
      this.saveCard = false});

  @override
  List<Object?> get props => [
        billingDetails,
        amount,
        distanceMiles,
        weightKg,
        selectedSpeed,
        paymentRequestId,
        deliveryId,
      ];
}

class UpdatePaymentStatus extends AccountEvent {
  final Map<String, dynamic> data;
  const UpdatePaymentStatus({required this.data});
}

class PaymentConfirmIntent extends AccountEvent {
  final String clientSecret;

  const PaymentConfirmIntent({required this.clientSecret});

  @override
  List<Object?> get props => [clientSecret];
}

class SaveCard extends AccountEvent {
  final bool val;
  SaveCard({required this.val});
}
