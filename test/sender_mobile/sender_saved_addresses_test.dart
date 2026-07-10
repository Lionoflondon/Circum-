import 'dart:async';
import 'dart:io';

import 'package:circum/app/sender_mobile/sender_saved_addresses.dart';
import 'package:circum/app/send_package/models/suggestions.m.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSavedAddressesRepository implements SenderSavedAddressesRepository {
  final controller = StreamController<List<SenderSavedAddress>>.broadcast();
  List<SenderSavedAddress> values;
  List<Suggestion> searchResults;
  Map<String, dynamic>? lastSave;
  String? deletedId;

  FakeSavedAddressesRepository(
      {this.values = const [], this.searchResults = const []});

  @override
  Stream<List<SenderSavedAddress>> watch() async* {
    yield values;
    yield* controller.stream;
  }

  @override
  Future<List<Suggestion>> search(String query) async => searchResults;
  @override
  Future<void> save(
      {String? addressId,
      required String label,
      required String customLabel,
      required Map<String, dynamic> address,
      required String deliveryInstructions,
      required bool isDefaultPickup,
      required bool isDefaultDropoff}) async {
    lastSave = {
      'addressId': addressId,
      'label': label,
      'customLabel': customLabel,
      'address': address,
      'deliveryInstructions': deliveryInstructions,
      'isDefaultPickup': isDefaultPickup,
      'isDefaultDropoff': isDefaultDropoff
    };
  }

  @override
  Future<void> delete(String addressId) async {
    deletedId = addressId;
  }
}

const canonical = <String, dynamic>{
  'formattedAddress': '10 Downing Street, London, SW1A 2AA, United Kingdom',
  'addressLine1': '10 Downing Street',
  'city': 'London',
  'postcode': 'SW1A 2AA',
  'country': 'United Kingdom',
  'placeId': 'place-1',
  'latitude': 51.5,
  'longitude': -0.1
};

SenderSavedAddress address(
        {String id = 'home',
        String label = 'home',
        String customLabel = '',
        bool pickup = false,
        bool dropoff = false}) =>
    SenderSavedAddress(
        id: id,
        label: label,
        customLabel: customLabel,
        address: canonical,
        deliveryInstructions: 'Ring once',
        isDefaultPickup: pickup,
        isDefaultDropoff: dropoff,
        version: 1);

Widget app(Widget child) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('empty state opens first address creation', (tester) async {
    final repo = FakeSavedAddressesRepository();
    await tester.pumpWidget(app(SenderSavedAddressesView(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('No saved addresses yet'), findsOneWidget);
    await tester.tap(find.text('Add Address'));
    await tester.pumpAndSettle();
    expect(find.text('Choose label'), findsOneWidget);
  });

  testWidgets(
      'autocomplete selection saves canonical Home address and defaults',
      (tester) async {
    final repo = FakeSavedAddressesRepository(searchResults: [
      Suggestion(
          placeId: 'place-1',
          description: canonical['formattedAddress']! as String,
          mainText: '10 Downing Street',
          subText: 'London, SW1A 2AA',
          lat: 51.5,
          lng: -0.1,
          components: canonical)
    ]);
    await tester.pumpWidget(app(SenderSavedAddressEditor(repository: repo)));
    await tester.enterText(
        find.widgetWithText(TextField, 'Search address or postcode'),
        'Downing');
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 Downing Street').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Set as default pickup'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pump();
    await tester.tap(find.byType(Switch).first);
    await tester.scrollUntilVisible(find.text('Review and save'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Review and save'));
    await tester.pumpAndSettle();
    expect(repo.lastSave?['label'], 'home');
    expect(repo.lastSave?['isDefaultPickup'], isTrue);
    expect((repo.lastSave?['address'] as Map)['postcode'], 'SW1A 2AA');
  });

  testWidgets('Other requires custom label and manual required fields',
      (tester) async {
    final repo = FakeSavedAddressesRepository();
    await tester.pumpWidget(app(SenderSavedAddressEditor(repository: repo)));
    await tester.tap(find.text('Other'));
    await tester.scrollUntilVisible(find.text('Review and save'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Review and save'));
    await tester.pump();
    expect(find.text('Add a custom label.'), findsOneWidget);
    expect(repo.lastSave, isNull);
  });

  testWidgets('editing preserves address id instead of creating another',
      (tester) async {
    final repo = FakeSavedAddressesRepository();
    await tester.pumpWidget(app(SenderSavedAddressEditor(
        repository: repo, existing: address(id: 'existing', label: 'work'))));
    await tester.scrollUntilVisible(find.text('Review and save'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Review and save'));
    await tester.pumpAndSettle();
    expect(repo.lastSave?['addressId'], 'existing');
    expect(repo.lastSave?['label'], 'work');
  });

  testWidgets('delete requires confirmation and warns for default',
      (tester) async {
    final item = address(pickup: true);
    final repo = FakeSavedAddressesRepository(values: [item]);
    await tester.pumpWidget(app(SenderSavedAddressesView(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete address').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('removes that default'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(repo.deletedId, item.id);
  });

  testWidgets('Profile preview and booking suggestion use the same address',
      (tester) async {
    final item = address(customLabel: 'Parents', label: 'other', pickup: true);
    final repo = FakeSavedAddressesRepository(values: [item]);
    SenderSavedAddress? selected;
    await tester.pumpWidget(app(Column(children: [
      SenderSavedAddressesProfileShortcut(repository: repo),
      SenderSavedAddressSuggestions(
          forPickup: true,
          repository: repo,
          onSelected: (value) => selected = value)
    ])));
    await tester.pumpAndSettle();
    expect(find.text('Parents · 10 Downing Street'), findsOneWidget);
    await tester.tap(find.text('Parents').last);
    expect(selected?.formattedAddress, item.formattedAddress);
    expect(selected?.toSuggestion().components['postcode'], 'SW1A 2AA');
  });

  test('Firestore rules protect saved address ownership and direct writes', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules, contains('match /savedAddresses/{addressId}'));
    expect(rules, contains('request.auth.uid == userId'));
    expect(rules, contains('allow create, update, delete: if false;'));
    final backend =
        File('server/functions/sender-saved-addresses.js').readAsStringSync();
    expect(backend, contains('context.auth.uid'));
    expect(backend, contains('db.runTransaction'));
    expect(backend, contains('isDefaultPickup'));
    expect(backend, contains('isDefaultDropoff'));
  });
}
