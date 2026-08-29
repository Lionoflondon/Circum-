import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final bloc = File('lib/app/send_package/bloc/send_package_bloc.dart')
      .readAsStringSync();
  final canvas = File('lib/app/sender_mobile/sender_booking_canvas.dart')
      .readAsStringSync();

  test('Sender payment and delivery callables cannot wait forever', () {
    expect(
        bloc, contains('const _senderCallableTimeout = Duration(seconds: 30)'));

    final callableMap = bloc.substring(
      bloc.indexOf('Future<Map<String, dynamic>> _callableMap'),
      bloc.indexOf('Future<void> _dispatchPaidDelivery'),
    );
    expect(callableMap, contains('.timeout(_senderCallableTimeout)'));
  });

  test('post-payment dispatch is bounded and recoverable', () {
    final dispatch = bloc.substring(
      bloc.indexOf('Future<void> _dispatchPaidDelivery'),
      bloc.indexOf('void _handleRequestSenderBookingQuote'),
    );

    expect(dispatch, contains("httpsCallable('sendPackage')"));
    expect(dispatch, contains('.timeout(_senderCallableTimeout)'));
    expect(dispatch, contains('catch (error)'));
    expect(dispatch, contains('delivery remains created'));
  });

  test('payment and delivery handlers always clear busy state on failures', () {
    final payment = bloc.substring(
      bloc.indexOf('void _handleStartSenderPaymentSession'),
      bloc.indexOf('void _handleCreatePaidSenderDelivery'),
    );
    expect(payment, contains("_callableMap('createSenderPaymentSession'"));
    expect(payment, contains('isSenderPaymentLoading: false'));
    expect(payment, contains('senderPaymentStatus: \'failed\''));
    expect(payment, contains("Payment couldn't be started. Please try again."));

    final delivery = bloc.substring(
      bloc.indexOf('void _handleCreatePaidSenderDelivery'),
      bloc.indexOf('void _handleFinalizeSenderWebCheckout'),
    );
    expect(delivery, contains("_callableMap('createSenderPaidDelivery'"));
    expect(delivery, contains('isSenderDeliveryCreating: false'));
    expect(delivery, contains('Delivery could not be created after payment.'));

    final checkout = bloc.substring(
      bloc.indexOf('void _handleFinalizeSenderWebCheckout'),
      bloc.indexOf('void _handleSendDeliveryRequestEvent'),
    );
    expect(checkout, contains("_callableMap('finalizeSenderWebCheckout'"));
    expect(checkout, contains('isSenderPaymentLoading: false'));
    expect(
      checkout,
      contains(
          'Stripe payment could not be confirmed. Please contact support.'),
    );
  });

  test('booking canvas keeps stable idempotency keys for retry/lost response',
      () {
    expect(canvas, contains("'idempotencyKey':"));
    expect(canvas, contains("'sender-\${senderUid ?? 'anonymous'}-"));
    expect(canvas, contains("\${engine.senderQuoteId ?? 'quote'}"));
    expect(canvas, contains("\${engine.senderPaymentSessionId ?? 'session'}"));
  });
}
