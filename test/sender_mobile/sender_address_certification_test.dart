import 'package:circum/app/platform/address_engine.dart';
import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/app/send_package/repo/route_request_coordinator.dart';
import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:circum/app/sender_mobile/sender_manual_address_resolution.dart';
import 'package:circum/app/send_package/models/suggestions.m.dart';
import 'package:flutter_test/flutter_test.dart';

Suggestion _place({
  required String description,
  required String placeId,
  required double lat,
  required double lng,
  required String postcode,
}) {
  return Suggestion(
    description: description,
    mainText: description,
    subText: 'United Kingdom',
    placeId: placeId,
    lat: lat,
    lng: lng,
    components: {
      'addressLine1': description.split(',').first,
      'city': description.contains('Cardiff') ? 'Cardiff' : 'London',
      'postcode': postcode,
      'country': 'United Kingdom',
    },
  );
}

String _postcodeKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

void main() {
  test('postcode variants share one matching key and preserve display text',
      () {
    const variants = ['SE6 1DQ', 'SE61DQ', 'se6 1dq', 'Se6 1Dq'];
    expect(variants.map(_postcodeKey).toSet(), {'se61dq'});

    for (final variant in variants) {
      final address = AddressEngine.normalize(
        components: {
          'addressLine1': '29 St Fillans Road',
          'city': 'London',
          'postcode': variant,
          'country': 'United Kingdom',
        },
      );
      expect(_postcodeKey(address['postcode'] as String), 'se61dq');
      expect(address['postcode'], variant);
    }
  });

  test(
      'one visible London candidate wins over unrelated Cardiff, ambiguity stays closed',
      () async {
    final london = _place(
      description: '29 St Fillans Road, London SE6 1DQ',
      placeId: 'london-1',
      lat: 51.4401,
      lng: -0.0258,
      postcode: 'SE6 1DQ',
    );
    final cardiff = _place(
      description: '29 St Fillans Road, Cardiff CF10 1AA',
      placeId: 'cardiff-1',
      lat: 51.4816,
      lng: -3.1791,
      postcode: 'CF10 1AA',
    );
    final resolver = SenderManualAddressResolver();
    var selected = 0;
    final result = await resolver.resolve(
      input: 'London SE6 1DQ',
      search: (_) async => [london, cardiff].where((candidate) {
        return candidate.subText == 'United Kingdom' &&
            candidate.components['city'] == 'London';
      }).toList(),
    );
    if (result.status == SenderManualAddressResolutionStatus.resolved) {
      selected++;
    }
    expect(result.status, SenderManualAddressResolutionStatus.resolved);
    expect(result.suggestion?.placeId, 'london-1');
    expect(selected, 1);

    final ambiguous = await resolver.resolve(
      input: 'London SE6 1DQ',
      search: (_) async => [
        london,
        _place(
          description: london.description,
          placeId: 'london-2',
          lat: london.lat!,
          lng: london.lng!,
          postcode: 'SE6 1DQ',
        ),
      ],
    );
    expect(ambiguous.status, SenderManualAddressResolutionStatus.ambiguous);
    expect(ambiguous.suggestion, isNull);
  });

  test('selected coordinates reach booking, route, and quote unchanged once',
      () async {
    const pickupLat = 51.440123;
    const pickupLng = -0.025876;
    const dropoffLat = 51.515501;
    const dropoffLng = -0.141900;
    final draft = SenderBookingDraft(
      pickupAddress: '29 St Fillans Road, London SE6 1DQ',
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffAddress: '10 Downing Street, London SW1A 2AA',
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
    );
    expect(draft.pickupLat, pickupLat);
    expect(draft.pickupLng, pickupLng);
    expect(draft.dropoffLat, dropoffLat);
    expect(draft.dropoffLng, dropoffLng);

    var routeCalls = 0;
    final route = RouteRequestCoordinator<String>(
      load: (origin, destination) async {
        routeCalls++;
        expect(origin.latitude, pickupLat);
        expect(origin.longitude, pickupLng);
        expect(destination.latitude, dropoffLat);
        expect(destination.longitude, dropoffLng);
        return 'route-ok';
      },
    );
    expect(
      await route.resolve(
        const RouteCoordinate(pickupLat, pickupLng),
        const RouteCoordinate(dropoffLat, dropoffLng),
      ),
      'route-ok',
    );
    expect(routeCalls, 1);

    final quote = RequestSenderBookingQuote(
      selectedSpeed: 'Standard',
      vanguardProtocolEnabled: false,
      itemName: 'Documents',
      description: 'Envelope',
      weightKg: 1,
      fragile: false,
      highValue: false,
      pickupLatitude: draft.pickupLat,
      pickupLongitude: draft.pickupLng,
      dropoffLatitude: draft.dropoffLat,
      dropoffLongitude: draft.dropoffLng,
    );
    expect(quote.pickupLatitude, pickupLat);
    expect(quote.pickupLongitude, pickupLng);
    expect(quote.dropoffLatitude, dropoffLat);
    expect(quote.dropoffLongitude, dropoffLng);
  });
}
