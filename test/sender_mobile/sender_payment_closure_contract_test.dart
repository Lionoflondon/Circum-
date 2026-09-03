import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checkout uses official platform wallet control without default copy',
      () {
    final source = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();
    expect(source, contains('PlatformPayButton('));
    expect(source, contains("ValueKey('senderApplePayButton')"));
    expect(source, contains("ValueKey('senderGooglePayButton')"));
    expect(source,
        isNot(contains("Google Pay\${option.isDefault ? ' · Default'")));
  });

  test('native payment sheets have explicit terminal bounds', () {
    for (final path in [
      'lib/app/sender_mobile/sender_booking_canvas.dart',
      'lib/app/sender_mobile/sender_wallet.dart',
      'lib/app/send_package/view/ratings.dart',
      'lib/app/account/bloc/account_bloc.dart',
      'lib/website/shared/circum_website_app.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('PaymentSheet'));
      expect(source, contains('.timeout('), reason: path);
    }
  });

  test('checkout checks backend payment mode before session creation', () {
    final source = File(
      'lib/app/send_package/bloc/send_package_bloc.dart',
    ).readAsStringSync();
    final modeCheck = source.indexOf("_callableMap('getSenderPaymentMode'");
    final session = source.indexOf("_callableMap('createSenderPaymentSession'");
    expect(modeCheck, greaterThan(0));
    expect(session, greaterThan(modeCheck));
    expect(source, contains('Env.paymentModeMatchesBackend'));
  });

  test('Directions credential is never compiled into Sender clients', () {
    final bloc = File(
      'lib/app/send_package/bloc/send_package_bloc.dart',
    ).readAsStringSync();
    final webBuild = File('scripts/build_sender_app_web.sh').readAsStringSync();
    expect(
        bloc,
        isNot(contains(
            "String.fromEnvironment('GOOGLE_MAPS_DIRECTIONS_API_KEY')")));
    expect(webBuild,
        isNot(contains('dart-define=GOOGLE_MAPS_DIRECTIONS_API_KEY')));
    expect(bloc, contains("'getSenderRoutePreview'"));
  });
}
