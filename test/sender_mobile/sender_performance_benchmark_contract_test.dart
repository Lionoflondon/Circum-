import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('performance benchmark artifact stays structured and non-sensitive', () {
    final source = File('scripts/performance_certification_benchmark.dart')
        .readAsStringSync();

    for (final field in const [
      'operation',
      'firstUiResponseMs',
      'authoritativeResponseMs',
      'firstIrisResponseMs',
      'authoritativeIrisResponseMs',
      'cacheHit',
      'fallbackUsed',
      'coldStartHint',
      'success',
    ]) {
      expect(source, contains("'$field'"));
    }

    expect(source, contains('record.keys.toSet().difference'));
    expect(source, contains('_allowedRecordFields'));
    expect(source, isNot(contains('clientSecret')));
    expect(source, isNot(contains('paymentIntent')));
    expect(source, isNot(contains('evidenceUrl')));
    expect(source, isNot(contains('latitude')));
    expect(source, isNot(contains('longitude')));
    expect(source, isNot(contains('postcode')));
  });

  test('performance benchmark covers the certification operations', () {
    final source = File('scripts/performance_certification_benchmark.dart')
        .readAsStringSync();

    for (final operation in const [
      'active_delivery_restore',
      'auth_restore',
      'iris_analysis',
      'address_search',
      'map_first_render',
      'sender_quote',
      'sender_payment_session',
      'sender_paid_delivery',
      'rider_acceptance',
      'lifecycle.',
    ]) {
      expect(source, contains(operation));
    }

    expect(source, contains('for (var index = 0; index < 50; index++)'));
    expect(source, contains('for (var index = 0; index < 30; index++)'));
    expect(source, contains('productionPayments'));
    expect(source, contains('productionDeliveries'));
    expect(source, contains('productionRiderAcceptances'));
    expect(source, contains('manualProductionFirestoreMutations'));
  });
}
