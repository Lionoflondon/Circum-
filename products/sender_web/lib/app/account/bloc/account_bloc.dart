import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

part 'account_event.dart';
part 'account_state.dart';

class AccountBloc extends Bloc<AccountEvent, AccountState> {
  AccountBloc() : super(const AccountState()) {
    on<PaymentStart>(_onPaymentStart);
    on<PaymentCreateIntent>(_onPaymentCreateIntent);
    on<PaymentConfirmIntent>(_onPaymentConfirmIntent);
    on<UpdatePaymentStatus>(_updatePaymentStatus);
    on<SaveCard>(_onSaveCard);
  }

  void _onSaveCard(
    SaveCard event,
    Emitter<AccountState> emit,
  ) {
    emit(state.copyWith(saveCard: event.val));
  }

  void _onPaymentStart(
    PaymentStart event,
    Emitter<AccountState> emit,
  ) {
    emit(state.copyWith(status: PaymentStatus.initial));
  }

  void _onPaymentCreateIntent(
    PaymentCreateIntent event,
    Emitter<AccountState> emit,
  ) async {
    emit(state.copyWith(status: PaymentStatus.failure));
  }

  void _onPaymentConfirmIntent(
    PaymentConfirmIntent event,
    Emitter<AccountState> emit,
  ) async {
    emit(state.copyWith(status: PaymentStatus.failure));
  }

  void _updatePaymentStatus(
      UpdatePaymentStatus event, Emitter<AccountState> emit) {
    if (event.data['success'] == true) {
      emit(state.copyWith(status: PaymentStatus.success));
    }
  }

  static Future<void> processPayment({
    required String clientIntentSecret,
    required String customerId,
    required String ephemeralKeySecret,
    required bool saveCard,
  }) async {
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientIntentSecret,
          customerId: customerId,
          customerEphemeralKeySecret: ephemeralKeySecret,
          style: ThemeMode.dark,
          merchantDisplayName: 'Circum',

          // savePaymentMethodOptions: PaymentSheetSavePaymentMethodOptions(
          //   backgroundColor: Colors.grey[800],
          //   textColor: Colors.white,
          // ),
        ),
      );

      await Stripe.instance.presentPaymentSheet();
    } catch (e) {
      throw Exception(e.toString());
    }
  }
}
