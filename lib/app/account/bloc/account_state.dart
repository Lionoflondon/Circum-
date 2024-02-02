part of 'account_bloc.dart';

enum PaymentStatus { initial, loading, success, failure }

class AccountState extends Equatable {
  final PaymentStatus status;
  final CardFieldInputDetails cardFieldInputDetails;

  const AccountState({
    this.status = PaymentStatus.initial,
    this.cardFieldInputDetails = const CardFieldInputDetails(complete: false),
  });

  AccountState copyWith({
    PaymentStatus? status,
    CardFieldInputDetails? cardFieldInputDetails,
  }) {
    return AccountState(
      status: status ?? this.status,
      cardFieldInputDetails:
          cardFieldInputDetails ?? this.cardFieldInputDetails,
    );
  }

  @override
  List<Object> get props => [status, cardFieldInputDetails];
}
