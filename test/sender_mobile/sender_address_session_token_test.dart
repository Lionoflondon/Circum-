import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('address provider sends the session token string unchanged', () {
    final provider = File(
      'lib/app/send_package/repo/place_api.dart',
    ).readAsStringSync();

    expect(provider, contains('final String sessionToken;'));
    expect(provider, contains("'sessionToken': sessionToken"));
    expect(provider, isNot(contains("'sessionToken': '\$sessionToken'")));
  });

  test('address call sites create string session-token values', () {
    final bloc = File(
      'lib/app/send_package/bloc/send_package_bloc.dart',
    ).readAsStringSync();
    final bookingCanvas = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();

    expect(bloc, contains('const Uuid().v4()'));
    expect(bookingCanvas, contains('PlaceApiProvider(const Uuid().v4())'));
    expect(bloc, isNot(contains('PlaceApiProvider(\n        uuid')));
  });

  test('selected place ids resolve once and pass coordinates into the bloc', () {
    final canvas = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();
    final bloc = File(
      'lib/app/send_package/bloc/send_package_bloc.dart',
    ).readAsStringSync();

    expect(canvas, contains('_selectedPickupPlaceId'));
    expect(canvas, contains('_selectedDropoffPlaceId'));
    expect(canvas, contains("final placeId = selectedPlaceId ?? match?.placeId;"));
    expect(canvas, contains('coordinate: coordinate'));
    expect(bloc, contains('final coordinate = event.coordinate ??'));
  });
}
