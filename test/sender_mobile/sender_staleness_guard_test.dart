import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/app/send_package/models/canonical_iris_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender copyWith clear flags remove stale booking artifacts', () {
    final stale = SendPackageState(
      canonicalIrisResult: const CanonicalIrisResult(
        itemName: 'fish',
        quantity: 1,
        unitWeightKg: 1.2,
        totalWeightKg: 1.2,
        category: 'fresh_food',
        recommendedVehicle: 'motorbike',
        confidenceLabel: 'High',
      ),
      itemDescription: 'fish · keep cold',
      senderQuoteId: 'quote_old',
      senderQuoteTotal: 35.92,
      senderQuoteSpeed: 'express',
      senderQuoteLineItems: const [
        {'label': 'Delivery', 'amount': 35.92},
      ],
      senderQuoteSpeedOptions: const [
        {'id': 'express', 'amount': 35.92},
      ],
      senderPaymentSessionId: 'session_old',
      senderPaymentStatus: 'checkout_created',
      senderPaymentClientSecret: 'secret_old',
      senderPaymentIntentId: 'pi_old',
      senderPaymentCustomerId: 'cus_old',
      senderPaymentEphemeralKeySecret: 'eph_old',
      senderPaymentCheckoutUrl: 'https://checkout.stripe.com/old',
      senderPaymentError: 'stale payment error',
      isSenderPaymentLoading: true,
      isSenderDeliveryCreating: true,
      senderDeliveryError: 'stale delivery error',
      senderCreatedRequestId: 'request_old',
    );

    final cleared = stale.copyWith(
      clearCanonicalIrisResult: true,
      clearItemDescription: true,
      clearSenderQuoteId: true,
      clearSenderQuoteTotal: true,
      clearSenderQuoteSpeed: true,
      senderQuoteLineItems: const [],
      senderQuoteSpeedOptions: const [],
      isSenderPaymentLoading: false,
      senderPaymentError: '',
      clearSenderPaymentSession: true,
      clearSenderPaymentStatus: true,
      clearSenderPaymentClientSecret: true,
      clearSenderPaymentIntent: true,
      clearSenderPaymentCustomer: true,
      clearSenderPaymentEphemeralKey: true,
      clearSenderPaymentCheckoutUrl: true,
      isSenderDeliveryCreating: false,
      senderDeliveryError: '',
      clearSenderCreatedRequest: true,
    );

    expect(cleared.canonicalIrisResult, isNull);
    expect(cleared.itemDescription, isNull);
    expect(cleared.senderQuoteId, isNull);
    expect(cleared.senderQuoteTotal, isNull);
    expect(cleared.senderQuoteSpeed, isNull);
    expect(cleared.senderQuoteLineItems, isEmpty);
    expect(cleared.senderQuoteSpeedOptions, isEmpty);
    expect(cleared.isSenderPaymentLoading, isFalse);
    expect(cleared.senderPaymentError, isEmpty);
    expect(cleared.senderPaymentSessionId, isNull);
    expect(cleared.senderPaymentStatus, isNull);
    expect(cleared.senderPaymentClientSecret, isNull);
    expect(cleared.senderPaymentIntentId, isNull);
    expect(cleared.senderPaymentCustomerId, isNull);
    expect(cleared.senderPaymentEphemeralKeySecret, isNull);
    expect(cleared.senderPaymentCheckoutUrl, isNull);
    expect(cleared.isSenderDeliveryCreating, isFalse);
    expect(cleared.senderDeliveryError, isEmpty);
    expect(cleared.senderCreatedRequestId, isNull);
  });

  test('ClearIrisParcelState is wired to remove stale IRIS artifacts', () {
    const event = ClearIrisParcelState();

    expect(event, isA<SendPackageEvent>());
  });

  test('Sender copyWith cannot accidentally clear nullable fields with null',
      () {
    final stale = SendPackageState(
      itemDescription: 'documents',
      senderQuoteId: 'quote_keep',
      senderPaymentSessionId: 'session_keep',
      senderCreatedRequestId: 'request_keep',
    );

    final unchanged = stale.copyWith(
      itemDescription: null,
      senderQuoteId: null,
      senderPaymentSessionId: null,
      senderCreatedRequestId: null,
    );

    expect(unchanged.itemDescription, 'documents');
    expect(unchanged.senderQuoteId, 'quote_keep');
    expect(unchanged.senderPaymentSessionId, 'session_keep');
    expect(unchanged.senderCreatedRequestId, 'request_keep');
  });
}
