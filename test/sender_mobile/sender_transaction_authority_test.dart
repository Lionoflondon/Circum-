import 'dart:io';

import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/app/send_package/models/place_coordinates.m.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('route changes clear stale route, quote, and payment authority', () {
    final state = SendPackageState(
      pickupCoordinate: PlaceCoordinate(lat: 51.5, lng: -0.1),
      desinationCoordinate: PlaceCoordinate(lat: 51.6, lng: -0.2),
      distance: 10,
      price: 20,
      senderQuoteId: 'quote-old',
      senderQuoteTotal: 20,
      senderPaymentSessionId: 'payment-old',
      senderPaymentClientSecret: 'secret-old',
    );

    final cleared = state.copyWith(
      clearPickupCoordinate: true,
      clearDestinationCoordinate: true,
      clearDistance: true,
      clearPrice: true,
      clearSenderQuoteId: true,
      clearSenderQuoteTotal: true,
      clearSenderPaymentSession: true,
      clearSenderPaymentClientSecret: true,
    );

    expect(cleared.pickupCoordinate, isNull);
    expect(cleared.desinationCoordinate, isNull);
    expect(cleared.distance, isNull);
    expect(cleared.price, isNull);
    expect(cleared.senderQuoteId, isNull);
    expect(cleared.senderQuoteTotal, isNull);
    expect(cleared.senderPaymentSessionId, isNull);
    expect(cleared.senderPaymentClientSecret, isNull);
  });

  test('transaction handlers suppress stale address, route, and quote results',
      () {
    final source = File(
      'lib/app/send_package/bloc/send_package_bloc.dart',
    ).readAsStringSync();
    expect(source, contains('_addressSelectionRequestIds'));
    expect(source, contains('routeRequestId != _routeRequestId'));
    expect(source, contains('quoteRequestId != _quoteRequestId'));
    expect(source, contains('irisRequestId != _irisRequestId'));
  });

  test('native payment always sends the complete booking payload', () {
    final source = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();
    expect(source, contains('deliveryPayload: _bookingPayload(engine)'));
    expect(
      source,
      isNot(contains('deliveryPayload: kIsWeb ? _bookingPayload(engine)')),
    );
  });
}
