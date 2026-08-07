import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) => File(path).readAsStringSync();

void main() {
  test('known delivery cancellation surfaces use canonical handlers', () {
    final tracking = _source('lib/app/sender_mobile/sender_tracking_screen.dart');
    final sendPackage = _source('lib/app/send_package/bloc/send_package_bloc.dart');
    final website = _source('lib/website/shared/circum_website_app.dart');
    final health = _source('lib/app/health_plus/view/health_plus.dart');
    final business = _source('lib/app/business/business_view.dart');

    expect(tracking, contains("_callFunction('requestSenderCancellation'"));
    expect(tracking, contains('onCancelDelivery'));
    expect(sendPackage, contains("httpsCallable('requestSenderCancellation')"));
    expect(website, contains("httpsCallable('cancelDelivery')"));
    expect(health, contains("httpsCallable('updateSenderHealthPlusBooking')"));

    // Business's operational toolbar is a navigation hint, not a cancellation
    // action; it must not advertise a cancel operation that it cannot perform.
    expect(business, isNot(contains("label: 'Cancel'")));
  });

  test('support remains an explicit separate action from Sender cancellation', () {
    final source = _source('lib/app/sender_mobile/sender_tracking_screen.dart');
    expect(source, contains('onOpenSupport'));
    expect(source, contains('onCancelDelivery'));
    expect(source, contains("_openSupportChat"));
    expect(source, contains("_callFunction('requestSenderCancellation'"));
  });
}
