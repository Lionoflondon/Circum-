import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Admin Gifts detail surfaces brief voice interests and payment first',
      () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    final briefIndex = source.indexOf('IRIS Gift Brief');
    final voiceIndex = source.indexOf('Voice Note');
    final interestsIndex = source.indexOf('Custom Interests Review');
    final paymentIndex = source.indexOf('Payment Breakdown');
    final rawIndex = source.indexOf('Raw request fields');

    expect(briefIndex, greaterThan(-1));
    expect(voiceIndex, greaterThan(briefIndex));
    expect(interestsIndex, greaterThan(voiceIndex));
    expect(paymentIndex, greaterThan(interestsIndex));
    expect(rawIndex, greaterThan(paymentIndex));
    expect(source, contains('Recipient summary'));
    expect(source, contains('Voice summary'));
    expect(source, contains('Play voice note'));
    expect(source, contains('Approve, reject, or merge these'));
    expect(source, contains('Roth applied'));
    expect(source, contains('Stripe session'));
  });
}
