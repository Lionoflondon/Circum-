part of 'account_bloc.dart';

enum PaymentStatus { initial, loading, success, failure }

class AccountState extends Equatable {
  final PaymentStatus status;
  final CardFieldInputDetails cardFieldInputDetails;
  final bool saveCard;
  final String? paymentIntentId;
  final String? quoteId;
  final String? paymentSessionId;
  final double? authoritativeAmount;

  const AccountState(
      {this.status = PaymentStatus.initial,
      this.cardFieldInputDetails = const CardFieldInputDetails(complete: false),
      this.saveCard = false,
      this.paymentIntentId,
      this.quoteId,
      this.paymentSessionId,
      this.authoritativeAmount});

  AccountState copyWith(
      {PaymentStatus? status,
      CardFieldInputDetails? cardFieldInputDetails,
      bool? saveCard,
      String? paymentIntentId,
      String? quoteId,
      String? paymentSessionId,
      double? authoritativeAmount}) {
    return AccountState(
        status: status ?? this.status,
        cardFieldInputDetails:
            cardFieldInputDetails ?? this.cardFieldInputDetails,
        saveCard: saveCard ?? this.saveCard,
        paymentIntentId: paymentIntentId ?? this.paymentIntentId,
        quoteId: quoteId ?? this.quoteId,
        paymentSessionId: paymentSessionId ?? this.paymentSessionId,
        authoritativeAmount: authoritativeAmount ?? this.authoritativeAmount);
  }

  @override
  List<Object?> get props => [
        status,
        cardFieldInputDetails,
        saveCard,
        paymentIntentId,
        quoteId,
        paymentSessionId,
        authoritativeAmount
      ];
}
