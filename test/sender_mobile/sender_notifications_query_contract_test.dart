import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sender notification streams use server ordering before limits', () {
    final centreSource =
        File('lib/app/sender_mobile/sender_notifications.dart')
            .readAsStringSync();
    final homeSource =
        File('lib/app/sender_mobile/sender_mobile_home.dart')
            .readAsStringSync();

    for (final source in [centreSource, homeSource]) {
      final recipient = source.indexOf(".where('recipientId', isEqualTo: uid)");
      final order = source.indexOf(".orderBy('createdAt', descending: true)");
      final limit = source.indexOf('.limit(', order);

      expect(recipient, isNonNegative);
      expect(order, greaterThan(recipient));
      expect(limit, greaterThan(order));
    }

    expect(centreSource, isNot(contains('results.sort(')));
    expect(homeSource, isNot(contains('items.sort(')));
  });
}
