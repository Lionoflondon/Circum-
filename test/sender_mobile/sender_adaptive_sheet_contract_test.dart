import 'dart:io';

import 'package:circum/app/sender_mobile/sender_booking_canvas.dart';
import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender booking uses the canonical draggable sheet contract', () {
    final source = File('lib/app/sender_mobile/sender_booking_canvas.dart')
        .readAsStringSync();

    expect(source, contains('DraggableScrollableSheet('));
    expect(source, contains('minChildSize: keyboardOpen ? .58 : .18'));
    expect(source, contains('const [.18, .45, .90]'));
    expect(source, contains('snapSizes: keyboardOpen'));
    expect(source, contains('maxChildSize: keyboardOpen ? .94 : .90'));
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

  test(
      'Sender booking sheet extents cover every booking step and keyboard state',
      () {
    for (final step in SenderBookingStep.values) {
      final resting = bookingSheetExtentForTest(step);
      expect(resting, inInclusiveRange(.18, .90), reason: step.name);
      expect(bookingSheetExtentForTest(step, true), .78, reason: step.name);
    }
    expect(bookingSheetExtentForTest(SenderBookingStep.parcel), .90);
    expect(bookingSheetExtentForTest(SenderBookingStep.iris), .90);
  });

  test('Sender booking sheet preserves Safari bottom clearance', () {
    final source = File('lib/app/sender_mobile/sender_booking_canvas.dart')
        .readAsStringSync();

    expect(source, contains('MediaQuery.viewPaddingOf(context)'));
    expect(source, contains('media.viewPadding.bottom'));
    expect(source, contains('media.viewInsets.bottom'));
    expect(source, contains('bottomClearance = bottomInset + 88'));
  });
}
