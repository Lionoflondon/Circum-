import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;

part 'account_event.dart';
part 'account_state.dart';

class AccountBloc extends Bloc<AccountEvent, AccountState> {
  FirebaseAuth auth = FirebaseAuth.instance;
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
    emit(state.copyWith(status: PaymentStatus.loading));

    final storage = FlutterSecureStorage();
    final pushToken = (await storage.readAll())["pushToken"];

    User? user = auth.currentUser;

    try {
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
          userId: user!.uid,
          name: user.displayName,
          email: event.email,
          pushToken: pushToken!,
          phone: user.phoneNumber,
          saveCard: event.saveCard);

      print(paymentIntentResult);

      if (paymentIntentResult['error'] != null) {
        // Error creating or confirming the payment intent.
        // print(paymentIntentResult['error']);
        emit(state.copyWith(status: PaymentStatus.failure));
      }

      if (paymentIntentResult['clientSecret'] != null &&
          paymentIntentResult['requiresAction'] == null) {
        // The payment succedeed / went through.
        // emit(state.copyWith(status: PaymentStatus.success));
      }

      if (paymentIntentResult['clientSecret'] != null &&
          paymentIntentResult['requiresAction'] == true) {
        final String clientSecret = paymentIntentResult['clientSecret'];
        add(PaymentConfirmIntent(clientSecret: clientSecret));
      } else {}
    } catch (e) {
      print('_onPaymentCreateIntent');
      print(e);
      emit(state.copyWith(status: PaymentStatus.failure));
    }
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

        print(results);

        if (results['error'] != null) {
          emit(state.copyWith(status: PaymentStatus.failure));
        } else {
          // emit(state.copyWith(status: PaymentStatus.success));
        }
      }
    } catch (err) {
      print(err);
      emit(state.copyWith(status: PaymentStatus.failure));
    }
  }

  void _updatePaymentStatus(
      UpdatePaymentStatus event, Emitter<AccountState> emit) {
    print(event.data);
    if (event.data['success'] == true) {
      emit(state.copyWith(status: PaymentStatus.success));
    }
  }

  Future<Map<String, dynamic>> _callPayEndpointMethodId({
    required bool useStripeSdk,
    required String paymentMethodId,
    required String currency,
    required bool saveCard,
    required String pushToken,
    required String userId,
    String? name,
    String? phone,
    String? email,
    int? amount,
  }) async {
    final url = Uri.parse(
      'https://us-central1-circum-2797c.cloudfunctions.net/StripePayEndpointMethodId',
    );

    final data = {
      'useStripeSdk': useStripeSdk,
      'paymentMethodId': paymentMethodId,
      'currency': currency,
      'amount': amount,
      'pushToken': pushToken,
      'email': email,
      'name': name,
      'phone': phone,
      'userId': userId
    };

    if (saveCard == true) {
      data['saveCard'] = saveCard;
    }

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(data),
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
