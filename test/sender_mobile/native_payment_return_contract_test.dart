import 'dart:io';

import 'package:circum/app/sender_mobile/native_payment_return.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native Stripe callback agrees across SDK and platform registration',
      () {
    final uri = Uri.parse(circumPaymentReturnUrl);
    expect(uri.scheme, circumPaymentUrlScheme);
    expect(uri.host, 'stripe-redirect');
    expect(File('ios/Runner/Info.plist').readAsStringSync(),
        contains('<string>$circumPaymentUrlScheme</string>'));
    expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains(
            'android:scheme="$circumPaymentUrlScheme" android:host="${uri.host}"'));
    expect(File('lib/main.dart').readAsStringSync(),
        contains('Stripe.urlScheme = circumPaymentUrlScheme'));
  });

  test('every Sender native payment sheet uses the registered callback', () {
    for (final path in [
      'lib/app/sender_mobile/sender_booking_canvas.dart',
      'lib/app/sender_mobile/gift_payment_view.dart',
      'lib/app/sender_mobile/sender_wallet.dart',
      'lib/app/send_package/view/ratings.dart',
      'lib/app/account/bloc/account_bloc.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect('SetupPaymentSheetParameters('.allMatches(source).length,
          'returnURL: nativePaymentReturnUrl'.allMatches(source).length,
          reason: path);
    }
  });
}
