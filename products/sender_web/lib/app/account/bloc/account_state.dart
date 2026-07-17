part of 'account_bloc.dart';

enum PaymentStatus { initial, loading, success, failure }

class AccountState extends Equatable {
  final PaymentStatus status;
  final CardFieldInputDetails cardFieldInputDetails;
  final bool saveCard;

  const AccountState(
      {this.status = PaymentStatus.initial,
      this.cardFieldInputDetails = const CardFieldInputDetails(complete: false),
      this.saveCard = false});

  AccountState copyWith(
      {PaymentStatus? status,
      CardFieldInputDetails? cardFieldInputDetails,
      bool? saveCard}) {
    return AccountState(
        status: status ?? this.status,
        cardFieldInputDetails:
            cardFieldInputDetails ?? this.cardFieldInputDetails,
        saveCard: saveCard ?? this.saveCard);
  }

  @override
  List<Object> get props => [status, cardFieldInputDetails, saveCard];
}
