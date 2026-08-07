import 'dart:async';

import 'package:circum/app/platform/address_engine.dart';
import 'package:circum/app/send_package/models/suggestions.m.dart';
import 'package:circum/app/sender_mobile/sender_saved_addresses.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSavedAddressesRepository implements SenderSavedAddressesRepository {
  _FakeSavedAddressesRepository({this.resolver});

  final Future<Suggestion> Function(Suggestion suggestion)? resolver;
  final List<Suggestion> searchResults = [];
  final List<String> resolvedPlaceIds = [];
  final List<Map<String, dynamic>> savedAddresses = [];

  @override
  Stream<List<SenderSavedAddress>> watch() => Stream.value(const []);

  @override
  Future<List<Suggestion>> search(String query) async => searchResults;

  @override
  Future<Suggestion> resolveSuggestion(Suggestion suggestion) async {
    resolvedPlaceIds.add(suggestion.placeId);
    if (resolver != null) return resolver!(suggestion);
    return suggestion;
  }

  @override
  Future<void> save({
    String? addressId,
    required String label,
    required String customLabel,
    required Map<String, dynamic> address,
    required String deliveryInstructions,
    required bool isDefaultPickup,
    required bool isDefaultDropoff,
  }) async {
    savedAddresses.add(address);
  }

  @override
  Future<void> delete(String addressId) async {}
}

Suggestion _googlePrediction({
  required String placeId,
  required String mainText,
  required String secondaryText,
}) {
  return Suggestion(
    placeId: placeId,
    description: '$mainText, $secondaryText',
    mainText: mainText,
    subText: secondaryText,
    components: {
      'addressLine1': mainText,
      'provider': 'google_places',
      'placeId': placeId,
    },
  );
}

Suggestion _googleCanonical({
  required String placeId,
  required String addressLine1,
  required String city,
  required String postcode,
  required double latitude,
  required double longitude,
}) {
  final address = {
    'addressLine1': addressLine1,
    'city': city,
    'postcode': postcode,
    'country': 'United Kingdom',
    'placeId': placeId,
    'provider': 'google_places',
    'latitude': latitude,
    'longitude': longitude,
  };
  return AddressEngine.suggestionFromCanonical(address);
}

Finder _field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );

Future<void> _openEditor(
  WidgetTester tester,
  _FakeSavedAddressesRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(home: SenderSavedAddressEditor(repository: repository)),
  );
  await tester.pump();
}

void main() {
  test('resolved backend data never derives fields from display text', () {
    final canonical = AddressEngine.canonicalFromBackend({
      'placeId': 'google-shard',
      'displayAddress': 'The Shard, 32 London Bridge Street, London SE1 9SG',
      'provider': 'google_places',
      'lat': 51.5045,
      'lng': -0.0865,
      'components': {
        'addressLine1': 'The Shard',
        'city': 'London',
        'postcode': 'SE1 9SG',
        'country': 'United Kingdom',
      },
    });

    expect(AddressEngine.isCanonical(canonical), isTrue);
    expect(canonical['city'], 'London');
    expect(canonical['postcode'], 'SE1 9SG');
    expect(canonical['city'], isNot('32 London Bridge Street'));
    expect(canonical['postcode'], isNot('London SE1 9SG'));
  });

  testWidgets('selecting The Shard resolves once and uses canonical fields', (
    tester,
  ) async {
    final prediction = _googlePrediction(
      placeId: 'google-shard',
      mainText: 'The Shard',
      secondaryText: '32 London Bridge Street, London SE1 9SG',
    );
    final repository = _FakeSavedAddressesRepository(
      resolver: (_) async => _googleCanonical(
        placeId: 'google-shard',
        addressLine1: 'The Shard',
        city: 'London',
        postcode: 'SE1 9SG',
        latitude: 51.5045,
        longitude: -0.0865,
      ),
    )..searchResults.add(prediction);

    await _openEditor(tester, repository);
    await tester.enterText(_field('Search address or postcode'), 'The Shard');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();

    expect(repository.resolvedPlaceIds, ['google-shard']);
    expect(tester.widget<TextField>(_field('City')).controller!.text, 'London');
    expect(
      tester.widget<TextField>(_field('Postcode')).controller!.text,
      'SE1 9SG',
    );
    expect(
      tester.widget<TextField>(_field('Postcode')).controller!.text,
      isNot('London SE1 9SG'),
    );
  });

  testWidgets('Save stays disabled while resolution is pending or invalid', (
    tester,
  ) async {
    final completer = Completer<Suggestion>();
    final prediction = _googlePrediction(
      placeId: 'google-pending',
      mainText: 'The Shard',
      secondaryText: '32 London Bridge Street, London SE1 9SG',
    );
    final repository = _FakeSavedAddressesRepository(
      resolver: (_) => completer.future,
    )..searchResults.add(prediction);

    await _openEditor(tester, repository);
    await tester.enterText(_field('Search address or postcode'), 'The Shard');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();

    await tester.fling(
      find.byType(ListView).first,
      const Offset(0, -1200),
      5000,
    );
    await tester.pump();
    expect(find.text('Verifying…'), findsOneWidget);
    expect(repository.savedAddresses, isEmpty);

    completer.completeError(StateError('resolver unavailable'));
    await tester.pump();
    await tester.pump();
    final saveText = find.text('Review and save');
    await tester.ensureVisible(saveText);
    await tester.tap(saveText, warnIfMissed: false);
    await tester.pump();
    expect(repository.savedAddresses, isEmpty);
  });

  testWidgets('a stale resolution cannot overwrite the latest selection', (
    tester,
  ) async {
    final first = Completer<Suggestion>();
    final second = Completer<Suggestion>();
    var calls = 0;
    final firstPrediction = _googlePrediction(
      placeId: 'google-a',
      mainText: 'The Shard',
      secondaryText: 'London SE1 9SG',
    );
    final secondPrediction = _googlePrediction(
      placeId: 'google-b',
      mainText: 'Battersea Power Station',
      secondaryText: 'Circus Road West, London SW11 8DD',
    );
    final repository = _FakeSavedAddressesRepository(
      resolver: (suggestion) {
        calls++;
        return calls == 1 ? first.future : second.future;
      },
    )
      ..searchResults.add(firstPrediction)
      ..searchResults.add(secondPrediction);

    await _openEditor(tester, repository);
    await tester.enterText(_field('Search address or postcode'), 'locations');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();

    await tester.enterText(_field('Search address or postcode'), 'locations 2');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.tap(find.byType(ListTile).at(1));
    await tester.pump();

    first.complete(
      _googleCanonical(
        placeId: 'google-a',
        addressLine1: 'The Shard',
        city: 'London',
        postcode: 'SE1 9SG',
        latitude: 51.5045,
        longitude: -0.0865,
      ),
    );
    await tester.pump();
    expect(
      tester.widget<TextField>(_field('City')).controller!.text,
      isNot('London'),
    );

    second.complete(
      _googleCanonical(
        placeId: 'google-b',
        addressLine1: 'Battersea Power Station',
        city: 'London',
        postcode: 'SW11 8DD',
        latitude: 51.4816,
        longitude: -0.1462,
      ),
    );
    await tester.pump();
    expect(repository.resolvedPlaceIds, ['google-a', 'google-b']);
    expect(
      tester.widget<TextField>(_field('Postcode')).controller!.text,
      'SW11 8DD',
    );
  });
}
