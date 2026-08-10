import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender home has no hardcoded personal fallback or fixed greeting', () {
    final source = File(
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ).readAsStringSync();
    expect(source, isNot(contains("_firstName == 'there' ? 'Ayo'")));
    expect(source, contains('greeting: _greeting'));
    expect(source, contains("'Good afternoon'"));
    expect(source, contains("'Good evening'"));
  });

  test('Sender page shells enforce their responsive maximum width', () {
    final source = File(
      'lib/app/sender_mobile/sender_page_shell.dart',
    ).readAsStringSync();
    expect(RegExp(r'clamp\(0\.0, maxWidth\)').allMatches(source).length, 2);
  });

  test('draft restoration overlaps local and backend preparation', () {
    final source = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();
    final localStart = source.indexOf('final localDraftFuture');
    final backendStart = source.indexOf("'loadSenderDraft'", localStart);
    final localAwait = source.indexOf('await localDraftFuture', localStart);
    expect(localStart, greaterThanOrEqualTo(0));
    expect(backendStart, greaterThan(localStart));
    expect(localAwait, greaterThan(backendStart));
    expect(source, contains('Sender draft restoration completed in'));
  });

  test('unresolved pickup is explicitly non-geographic', () {
    final source = File(
      'lib/app/sender_mobile/sender_booking_canvas.dart',
    ).readAsStringSync();
    expect(source, contains('_UnresolvedPickupMapPlaceholder'));
    expect(source, contains('Choose pickup to show route'));
    expect(source, contains('No route map yet'));
  });

  test('Google Maps script does not block Sender startup', () {
    final source = File('scripts/build_sender_app_web.sh').readAsStringSync();
    expect(source, contains('<script async defer src='));
    expect(source, contains('&loading=async'));
  });
}
