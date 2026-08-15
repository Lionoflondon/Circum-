import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer legal links use leave-app confirmation helper', () {
    final files = [
      File('lib/app/onboarding/view/onboarding.dart'),
      File('lib/app/account/view/account.dart'),
      File('lib/app/sender_mobile/sender_mobile_profile.dart'),
    ];
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, contains('openCircumLegalLink'));
      expect(
        source,
        isNot(contains("launchUrl(Uri.parse('https://circumuk.com/terms'))")),
      );
      expect(
        source,
        isNot(contains("launchUrl(Uri.parse('https://circumuk.com/privacy'))")),
      );
    }
  });

  test('legal external navigation is explicit allow-list only', () {
    final source =
        File('lib/app/platform/external_navigation.dart').readAsStringSync();
    expect(source, contains("uri.host == 'circumuk.com'"));
    expect(source, contains("uri.path == '/terms'"));
    expect(source, contains("uri.path == '/privacy'"));
    expect(source, contains("You're leaving CIRCUM"));
    expect(source, contains('This link will open outside the CIRCUM app.'));
    expect(source, contains('LaunchMode.externalApplication'));
  });
}
