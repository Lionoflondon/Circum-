import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Business Gifts labels recipient privacy without inventing a status count',
    () {
      final source = File(
        'lib/app/business/business_view.dart',
      ).readAsStringSync();

      expect(source, contains("label: 'Recipient privacy'"));
      expect(source, contains("value: 'Protected'"));
      expect(source, isNot(contains("item.status.contains('recipient')")));
    },
  );
}
