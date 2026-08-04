import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('specific typed addresses do not suppress returned suggestions', () {
    final source = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'if (controller.text.trim().isNotEmpty && suggestions.isNotEmpty)',
      ),
    );
    expect(
      source,
      isNot(
        contains(
          'if (controller.text.trim().isNotEmpty && !canContinue)\n'
          '          ConstrainedBox(',
        ),
      ),
    );
  });
}
