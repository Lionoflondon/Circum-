part of 'account_bloc.dart';

enum PaymentStatus { initial, loading, success, failure }

class AccountState extends Equatable {
  final PaymentStatus status;
  final CardFieldInputDetails cardFieldInputDetails;
  final bool saveCard;
  final String? paymentIntentId;

  const AccountState(
      {this.status = PaymentStatus.initial,
      this.cardFieldInputDetails = const CardFieldInputDetails(complete: false),
      this.saveCard = false,
      this.paymentIntentId});

  AccountState copyWith(
      {PaymentStatus? status,
      CardFieldInputDetails? cardFieldInputDetails,
      bool? saveCard,
      String? paymentIntentId}) {
    return AccountState(
        status: status ?? this.status,
        cardFieldInputDetails:
            cardFieldInputDetails ?? this.cardFieldInputDetails,
        saveCard: saveCard ?? this.saveCard,
        paymentIntentId: paymentIntentId ?? this.paymentIntentId);
  }

  @override
  List<Object?> get props =>
      [status, cardFieldInputDetails, saveCard, paymentIntentId];
}
