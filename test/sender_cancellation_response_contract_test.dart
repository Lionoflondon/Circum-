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

  test('searching actions keep support and cancellation independently wired', () {
    expect(source, contains("'Message Support'"));
    expect(source, contains('onOpenSupport'));
    expect(source, contains("'Cancel Delivery'"));
    expect(source, contains('onCancelDelivery'));
    expect(source, contains('if (confirmed != true) return;'));
    expect(source, contains("_callFunction('requestSenderCancellation'"));
  });

  test('searching action hit targets are separate expanded row children', () {
    final actionsStart = source.indexOf('class _TrackingActions');
    final actionsEnd = source.indexOf('class _TrackingButton', actionsStart);
    final actions = source.substring(actionsStart, actionsEnd);
    expect(RegExp(r'Expanded\(').allMatches(actions), hasLength(2));
    expect(actions, contains('const SizedBox(width: 8)'));
  });
}
