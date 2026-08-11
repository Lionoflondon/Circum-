import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender booking uses the canonical draggable sheet contract', () {
    final source = File('lib/app/sender_mobile/sender_booking_canvas.dart')
        .readAsStringSync();

    expect(source, contains('DraggableScrollableSheet('));
    expect(source, contains('minChildSize: .18'));
    expect(source, contains('snapSizes: const [.18, .45, .90]'));
    expect(source, contains('maxChildSize: .90'));
    expect(source, contains('controller: scrollController'));
    expect(source, contains('_bookingSheetExtentFor'));
  });

  test('Sender tracking preserves map sheet extents and adds semantics', () {
    final source = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();

    expect(source, contains('minChildSize: .24'));
    expect(source, contains('snapSizes: const [.38, .78]'));
    expect(source, contains('maxChildSize: .78'));
    expect(source, contains("label: 'Delivery details'"));
    expect(source, contains('onIncrease:'));
    expect(source, contains('onDecrease:'));
    expect(source, contains('_adaptSheetToState'));
  });

  test('Sender adaptive closure stays inside Sender App ownership', () {
    final booking = File('lib/app/sender_mobile/sender_booking_canvas.dart')
        .readAsStringSync();
    final tracking = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();

    expect(booking, isNot(contains('lib/website/')));
    expect(tracking, isNot(contains('lib/website/')));
  });
}
