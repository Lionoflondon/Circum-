import 'dart:async';

import 'package:circum/app/send_package/models/suggestions.m.dart';
import 'package:circum/app/sender_mobile/sender_manual_address_resolution.dart';
import 'package:flutter_test/flutter_test.dart';

Suggestion suggestion(String address, {double? lat, double? lng}) => Suggestion(
      description: address,
      mainText: address,
      subText: 'London, UK',
      placeId: 'place-$address',
      lat: lat,
      lng: lng,
    );

void main() {
  test('unique manual address resolves through the canonical candidate',
      () async {
    final resolver = SenderManualAddressResolver();
    final result = await resolver.resolve(
      input: '10 Downing Street, London',
      search: (_) async =>
          [suggestion('10 Downing Street, London', lat: 51.5, lng: -0.1)],
    );
    expect(result.status, SenderManualAddressResolutionStatus.resolved);
    expect(result.suggestion?.lat, 51.5);
    expect(result.suggestion?.lng, -0.1);
  });

  test('multiple candidates require explicit selection', () async {
    final result = await SenderManualAddressResolver().resolve(
      input: 'High Street',
      search: (_) async =>
          [suggestion('High Street A'), suggestion('High Street B')],
    );
    expect(result.status, SenderManualAddressResolutionStatus.ambiguous);
    expect(result.suggestion, isNull);
  });

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
    final oldRequest =
        resolver.resolve(input: 'Address A', search: (_) => first.future);
    final latest = await resolver.resolve(
      input: 'Address B',
      search: (_) async => [suggestion('Address B')],
    );
    first.complete([suggestion('Address A')]);
    expect(latest.status, SenderManualAddressResolutionStatus.resolved);
    expect(
        (await oldRequest).status, SenderManualAddressResolutionStatus.stale);
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
