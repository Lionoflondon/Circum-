import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/app/sender_mobile/sender_tracking_screen.dart')
      .readAsStringSync();

  test('sender cancellation checks callable success before showing success', () {
    expect(source, contains("result['success'] != true"));
    expect(source, contains("Delivery cancellation sent."));
    expect(source, contains("result['decision']"));
  });
}
