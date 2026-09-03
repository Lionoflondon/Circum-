import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

part 'account_event.dart';
part 'account_state.dart';

const _accountPaymentSheetInitTimeout = Duration(seconds: 20);
const _accountPaymentSheetPresentTimeout = Duration(seconds: 90);

class AccountBloc extends Bloc<AccountEvent, AccountState> {
  FirebaseAuth auth = FirebaseAuth.instance;
  AccountBloc() : super(const AccountState()) {
    on<PaymentStart>(_onPaymentStart);
    on<PaymentCreateIntent>(_onPaymentCreateIntent);
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
    emit(state.copyWith(status: PaymentStatus.loading));

    try {
      // final paymentMethod = await Stripe.instance.createPaymentMethod(
      //   params: PaymentMethodParams.card(
      //     paymentMethodData: PaymentMethodData(
      //       billingDetails: event.billingDetails,
      //     ),
      //   ),
      // );

      final paymentIntentResult = await _createSenderPaymentSession(
          currency: 'gbp',
          clientDisplayAmount: event.amount,
          distanceMiles: event.distanceMiles,
          weightKg: event.weightKg,
          selectedSpeed: event.selectedSpeed,
          paymentRequestId: event.paymentRequestId,
          saveCard: event.saveCard);

      if (paymentIntentResult['error'] != null) {
        // Error creating or confirming the payment intent.
        // print(paymentIntentResult['error']);
        emit(state.copyWith(status: PaymentStatus.failure));
      }

      if (paymentIntentResult['clientSecret'] != null) {
        await processPayment(
            clientIntentSecret: paymentIntentResult['clientSecret'],
            ephemeralKeySecret: paymentIntentResult['ephemeralKeySecret'],
            customerId: paymentIntentResult['customerId'],
            saveCard: event.saveCard);
      }

      if (paymentIntentResult['paymentSessionId'] != null) {
        emit(state.copyWith(
            status: PaymentStatus.success,
            paymentIntentId:
                paymentIntentResult['stripePaymentIntentId'] as String?,
            quoteId: paymentIntentResult['quoteId'] as String?,
            paymentSessionId:
                paymentIntentResult['paymentSessionId'] as String?,
            authoritativeAmount:
                (paymentIntentResult['amountDue'] as num?)?.toDouble()));
      }
    } catch (_) {
      emit(state.copyWith(status: PaymentStatus.failure));
    }
  }

  void _updatePaymentStatus(
      UpdatePaymentStatus event, Emitter<AccountState> emit) {
    if (event.data['success'] == true) {
      emit(state.copyWith(status: PaymentStatus.success));
    }
  }

  Future<Map<String, dynamic>> _createSenderPaymentSession({
    required String currency,
    required bool saveCard,
    int? clientDisplayAmount,
    double? distanceMiles,
    double? weightKg,
    String? selectedSpeed,
    String? paymentRequestId,
  }) async {
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final quoteResponse =
        await functions.httpsCallable('createSenderBookingQuote').call({
      'quoteId': paymentRequestId,
      'currency': currency.toUpperCase(),
      'clientDisplayQuote': {
        'amountPence': clientDisplayAmount,
        'amount':
            clientDisplayAmount == null ? null : clientDisplayAmount / 100,
        'currency': currency.toUpperCase(),
      },
      'pricingInput': {
        'distanceMiles': distanceMiles,
        'weightKg': weightKg,
        'selectedSpeed': selectedSpeed ?? 'standard',
      },
      'distanceMiles': distanceMiles,
      'weightKg': weightKg,
      'selectedSpeed': selectedSpeed ?? 'standard',
    });
    final quote = Map<String, dynamic>.from(quoteResponse.data as Map);
    final sessionResponse =
        await functions.httpsCallable('createSenderPaymentSession').call({
      'quoteId': quote['quoteId'],
      'fallbackMethod': 'card',
      'saveCard': saveCard,
    });
    final session = Map<String, dynamic>.from(sessionResponse.data as Map);
    return {
      ...session,
      'quoteId': quote['quoteId'],
      'authoritativeQuote': quote,
      'amountDue': quote['amountDue'] ?? quote['total'],
    };
  }

  static Future<void> processPayment({
    required String clientIntentSecret,
    required String customerId,
    required String ephemeralKeySecret,
    required bool saveCard,
  }) async {
    try {
      await Stripe.instance
          .initPaymentSheet(
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
          )
          .timeout(_accountPaymentSheetInitTimeout);

      await Stripe.instance
          .presentPaymentSheet()
          .timeout(_accountPaymentSheetPresentTimeout);
    } catch (e) {
      throw Exception(e.toString());
    }
  }
}
