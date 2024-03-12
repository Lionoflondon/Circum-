part of 'account_bloc.dart';

abstract class AccountEvent extends Equatable {
  const AccountEvent();

  @override
  List<Object?> get props => [];
}

class PaymentStart extends AccountEvent {}

class PaymentCreateIntent extends AccountEvent {
  final BillingDetails billingDetails;
  final int amount;
  final bool saveCard;

  const PaymentCreateIntent(
      {required this.billingDetails,
      required this.amount,
      this.saveCard = false});

  @override
  List<Object?> get props => [billingDetails, amount];
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
