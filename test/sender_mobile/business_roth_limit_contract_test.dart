import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native Business Roth matches the £1m backend limit', () {
    final repository =
        File('lib/app/business/business_repository.dart').readAsStringSync();
    final view = File('lib/app/business/business_view.dart').readAsStringSync();

    expect(repository, contains('amount > 1000000'));
    expect(repository, isNot(matches(RegExp(r'amount > 10000\s*\|\|'))));
    expect(view, contains('Maximum £1,000,000'));
    expect(view, contains('parsed > 1000000'));
    expect(view, contains('Business Roth purchases are non-refundable.'));
  });
}
