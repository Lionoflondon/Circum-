import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test(
    'typed Sender address confirmation uses backend resolution directly',
    () {
      final placeApi = read('lib/app/send_package/repo/place_api.dart');
      final canvas = read('lib/app/sender_mobile/sender_booking_canvas.dart');

      expect(placeApi, contains('Future<Suggestion> resolveTypedAddress'));
      expect(placeApi, contains("httpsCallable('searchFreeUkAddresses')"));
      expect(placeApi, contains("httpsCallable('resolveUkAddressPlace')"));
      expect(placeApi, contains("'sourceInput': sourceInput!.trim()"));
      expect(canvas, contains('provider.resolveTypedAddress(address, lang)'));
      expect(canvas, contains('_pickup.text = resolved.description'));
      expect(canvas, contains('_dropoff.text = resolved.description'));
      expect(canvas, contains('pickupLat: lat'));
      expect(canvas, contains('dropoffLat: lat'));
      expect(
        canvas,
        isNot(contains('Please choose a matching address suggestion')),
      );
    },
  );

  test(
    'address formatter preserves premise metadata and avoids duplicates',
    () {
      final appEngine = read('lib/app/platform/address_engine.dart');

      expect(appEngine, contains('joinDistinctParts'));
      expect(appEngine, contains("'buildingNumber': streetNumber"));
      expect(appEngine, contains("'street': route"));
      expect(appEngine, contains("'resolutionPrecision': firstPart"));
    },
  );
}
