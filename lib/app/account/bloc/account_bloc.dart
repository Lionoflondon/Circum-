import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;

part 'account_event.dart';
part 'account_state.dart';

class AccountBloc extends Bloc<AccountEvent, AccountState> {
  AccountBloc() : super(const AccountState()) {
    on<PaymentStart>(_onPaymentStart);
    on<PaymentCreateIntent>(_onPaymentCreateIntent);
    on<PaymentConfirmIntent>(_onPaymentConfirmIntent);
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
    emit(state.copyWith(status: PaymentStatus.loading));

    final paymentMethod = await Stripe.instance.createPaymentMethod(
      params: PaymentMethodParams.card(
        paymentMethodData: PaymentMethodData(
          billingDetails: event.billingDetails,
        ),
      ),
    );

    final paymentIntentResult = await _callPayEndpointMethodId(
      useStripeSdk: true,
      paymentMethodId: paymentMethod.id,
      currency: 'gbp',
      amount: event.amount,
    );

    if (paymentIntentResult['error'] != null) {
      // Error creating or confirming the payment intent.
      // print(paymentIntentResult['error']);
      emit(state.copyWith(status: PaymentStatus.failure));
    }

    if (paymentIntentResult['clientSecret'] != null &&
        paymentIntentResult['requiresAction'] == null) {
      // The payment succedeed / went through.
      emit(state.copyWith(status: PaymentStatus.success));
    }

    if (paymentIntentResult['clientSecret'] != null &&
        paymentIntentResult['requiresAction'] == true) {
      final String clientSecret = paymentIntentResult['clientSecret'];
      add(PaymentConfirmIntent(clientSecret: clientSecret));
    } else {}
  }

  void _onPaymentConfirmIntent(
    PaymentConfirmIntent event,
    Emitter<AccountState> emit,
  ) async {
    // The payment requires action calling handleNextAction
    try {
      final paymentIntent =
          await Stripe.instance.handleNextAction(event.clientSecret);

      if (paymentIntent.status == PaymentIntentsStatus.RequiresConfirmation) {
        // Call API to confirm intent
        Map<String, dynamic> results =
            await _callPayEndpointIntentId(paymentIntentId: paymentIntent.id);

        if (results['error'] != null) {
          emit(state.copyWith(status: PaymentStatus.failure));
        } else {
          emit(state.copyWith(status: PaymentStatus.success));
        }
      }
    } catch (err) {
      print(err);
      emit(state.copyWith(status: PaymentStatus.failure));
    }
  }

  Future<Map<String, dynamic>> _callPayEndpointMethodId({
    required bool useStripeSdk,
    required String paymentMethodId,
    required String currency,
    int? amount,
  }) async {
    final url = Uri.parse(
      'https://us-central1-circum-2797c.cloudfunctions.net/StripePayEndpointMethodId',
    );
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'useStripeSdk': useStripeSdk,
        'paymentMethodId': paymentMethodId,
        'currency': currency,
        'amount': amount
      }),
    );
    return json.decode(response.body);
  }

  Future<Map<String, dynamic>> _callPayEndpointIntentId({
    required String paymentIntentId,
  }) async {
    final url = Uri.parse(
      'https://us-central1-circum-2797c.cloudfunctions.net/StripePayEndpointIntentId',
    );
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'paymentIntentId': paymentIntentId,
      }),
    );
    return json.decode(response.body);
  }
}
