import 'dart:io';

import 'package:circum/app/sender_mobile/design_system/sender_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long cinematic status fits a narrow Sender viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 288,
            child: SenderCinematicHeading('Finding your Circum Rider'),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text('FINDING YOUR CIRCUM RIDER'));
    expect(text.style?.fontFamily, SenderTypography.cinematicFontFamily);
    expect(text.style?.fontWeight, FontWeight.w600);
    expect(text.style!.letterSpacing, lessThan(2));
  });

  test('cinematic typography is scoped from Review onward', () {
    final booking = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();
    final tracking = File(
      'lib/app/sender_mobile/sender_tracking_screen.dart',
    ).readAsStringSync();

    expect(
      booking,
      contains("draft.step == SenderBookingStep.payment"),
    );
    expect(booking, contains("'Review your delivery'"));
    expect(
      booking,
      contains('SenderCinematicHeading(senderStepTitle(draft.step))'),
    );
    expect(tracking,
        contains('SenderCinematicHeading(\n            content.title'));
    expect(tracking, contains("'Delivery receipt'"));

    final paymentGate = booking.indexOf(
      'if (draft.step == SenderBookingStep.payment)',
    );
    final normalHeading = booking.indexOf(
      'Text(\n                    senderStepTitle(draft.step)',
      paymentGate,
    );
    expect(paymentGate, greaterThan(-1));
    expect(normalHeading, greaterThan(paymentGate));
  });

  test('financial, address and body text remain outside cinematic primitive',
      () {
    final booking = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();
    final tracking = File(
      'lib/app/sender_mobile/sender_tracking_screen.dart',
    ).readAsStringSync();

    expect(booking, isNot(contains('SenderCinematicHeading(total')));
    expect(booking, isNot(contains('SenderCinematicHeading(pickup')));
    expect(booking, isNot(contains('SenderCinematicHeading(dropoff')));
    expect(tracking, isNot(contains('SenderCinematicHeading(content.body')));
    expect(tracking, isNot(contains('SenderCinematicHeading(receipt.amount')));
  });
}
