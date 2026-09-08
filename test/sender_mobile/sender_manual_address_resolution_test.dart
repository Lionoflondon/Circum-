import 'dart:async';

import 'package:circum/app/send_package/models/suggestions.m.dart';
import 'package:circum/app/sender_mobile/sender_manual_address_resolution.dart';
import 'package:flutter_test/flutter_test.dart';

Suggestion suggestion(String address, {double? lat, double? lng}) {
  final parts = address.split(',').map((part) => part.trim()).toList();
  final subText = parts.length <= 1 ? address : parts.skip(1).join(', ');
  return Suggestion(
    description: address,
    mainText: parts.first,
    subText: subText,
    placeId: 'place-$address',
    lat: lat,
    lng: lng,
  );
}

void main() {
  test('London alone selects only the London candidate', () {
    final result = senderBestAddressSuggestionForInput('London', [
      suggestion('124 City Road, London'),
      suggestion('124 City Road, Cardiff'),
    ]);
    expect(result?.description, contains('London'));
  });

  for (final input in ['London SE6 1DQ', 'London SE61DQ', 'London se6 1dq']) {
    for (final candidate in ['SE6 1DQ', 'SE61DQ', 'se6 1dq']) {
      test('$input matches candidate postcode $candidate', () {
        final result = senderBestAddressSuggestionForInput(input, [
          suggestion('29 St Fillans Rd, London $candidate'),
          suggestion('29 St Fillans Rd, Kirkcaldy KY1 1AA'),
        ]);
        expect(result?.description, contains('London'));
      });
    }
  }

  for (final input in ['London', 'London SE6', 'London SE6 1DQ']) {
    test('$input does not guess between plausible addresses', () {
      expect(
        senderBestAddressSuggestionForInput(input, [
          suggestion('29 St Fillans Rd, London SE6 1DQ'),
          suggestion('31 St Fillans Rd, London SE6 1DQ'),
        ]),
        isNull,
      );
    });
  }

  test(
    'unique manual address resolves through the canonical candidate',
    () async {
      final resolver = SenderManualAddressResolver();
      final result = await resolver.resolve(
        input: '10 Downing Street, London',
        search: (_) async => [
          suggestion('10 Downing Street, London', lat: 51.5, lng: -0.1),
        ],
      );
      expect(result.status, SenderManualAddressResolutionStatus.resolved);
      expect(result.suggestion?.lat, 51.5);
      expect(result.suggestion?.lng, -0.1);
    },
  );

  test('multiple candidates require explicit selection', () async {
    final result = await SenderManualAddressResolver().resolve(
      input: 'High Street',
      search: (_) async => [
        suggestion('High Street A'),
        suggestion('High Street B'),
      ],
    );
    expect(result.status, SenderManualAddressResolutionStatus.ambiguous);
    expect(result.suggestion, isNull);
  });

  test('typed city narrows visible address candidates', () async {
    final result = await SenderManualAddressResolver().resolve(
      input: '124 City Road, London, United Kingdom',
      search: (_) async => [
        suggestion('124 City Road, London, United Kingdom'),
        suggestion('124 City Road, Cardiff, United Kingdom'),
      ],
    );
    expect(result.status, SenderManualAddressResolutionStatus.resolved);
    expect(result.suggestion?.description, contains('London'));
  });

  test('ambiguous street without locality still requires selection', () async {
    final result = await SenderManualAddressResolver().resolve(
      input: '124 City Road',
      search: (_) async => [
        suggestion('124 City Road, London, United Kingdom'),
        suggestion('124 City Road, Cardiff, United Kingdom'),
      ],
    );
    expect(result.status, SenderManualAddressResolutionStatus.ambiguous);
    expect(result.suggestion, isNull);
  });

  test(
    'postcode narrows a duplicated typed address to the matching suggestion',
    () {
      final result = senderBestAddressSuggestionForInput(
        '29 St Fillans Rd, 29 St Fillans Rd, London SE6 1DQ, United Kingdom',
        [
          suggestion('29 St Fillans Rd, Kirkcaldy, United Kingdom'),
          suggestion('29 St Fillans Rd, London SE6 1DQ, United Kingdom'),
        ],
      );

      expect(result?.description, contains('London'));
    },
  );

  test('no match remains unresolved', () async {
    final result = await SenderManualAddressResolver().resolve(
      input: 'Missing address',
      search: (_) async => [],
    );
    expect(result.status, SenderManualAddressResolutionStatus.noMatch);
  });

  test('older resolution cannot overwrite newer input', () async {
    final resolver = SenderManualAddressResolver();
    final first = Completer<List<Suggestion>>();
    final oldRequest = resolver.resolve(
      input: 'Address A',
      search: (_) => first.future,
    );
    final latest = await resolver.resolve(
      input: 'Address B',
      search: (_) async => [suggestion('Address B')],
    );
    first.complete([suggestion('Address A')]);
    expect(latest.status, SenderManualAddressResolutionStatus.resolved);
    expect(
      (await oldRequest).status,
      SenderManualAddressResolutionStatus.stale,
    );
  });

  test('timeout terminates safely', () async {
    final result = await SenderManualAddressResolver().resolve(
      input: 'Slow address',
      timeout: const Duration(milliseconds: 1),
      search: (_) => Completer<List<Suggestion>>().future,
    );
    expect(result.status, SenderManualAddressResolutionStatus.timeout);
  });
}
