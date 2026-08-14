import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Sender external navigation is centralized and default-deny', () {
    final authority = read(
      'lib/app/sender_mobile/sender_external_navigation.dart',
    );

    expect(authority, contains('class SenderExternalNavigation'));
    expect(authority, contains('enum SenderExternalDestination'));
    expect(authority, contains('terms'));
    expect(authority, contains('privacy'));
    expect(authority, contains('approvedStripePayment'));
    expect(authority, contains("You're leaving CIRCUM"));
    expect(authority, contains('This link will open outside the CIRCUM app.'));
    expect(authority, contains('return false;'));
  });

  test('Sender source has no uncontrolled browser launch calls', () {
    final allowedLaunchFile =
        'lib/app/sender_mobile/sender_external_navigation.dart';
    final roots = [
      Directory('lib/app/sender_mobile'),
      Directory('lib/app/account'),
      Directory('lib/app/health_plus'),
      Directory('lib/app/onboarding'),
    ];
    final offenders = <String>[];

    for (final root in roots) {
      for (final file in root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))) {
        final normalized = file.path.replaceAll('\\', '/');
        final source = file.readAsStringSync();
        if (normalized.endsWith(allowedLaunchFile)) continue;
        if (source.contains('launchUrl(') ||
            source.contains('launchUrlString(')) {
          offenders.add(normalized);
        }
      }
    }

    expect(offenders, isEmpty);
  });

  test('Sender Wallet Manage Payments cannot route to Business UI', () {
    final wallet = read('lib/app/sender_mobile/sender_wallet.dart');
    expect(wallet, isNot(contains('BusinessView')));
    expect(wallet, isNot(contains('Manage Business Payments')));
    expect(wallet, isNot(contains('Create Business Account')));
  });

  test('Terms and Privacy use warning authority', () {
    final profile = read('lib/app/sender_mobile/sender_mobile_profile.dart');
    final account = read('lib/app/account/view/account.dart');
    final onboarding = read('lib/app/onboarding/view/onboarding.dart');

    expect(profile, contains('SenderExternalNavigation.open'));
    expect(profile, contains('SenderExternalDestination.terms'));
    expect(profile, contains('SenderExternalDestination.privacy'));
    expect(account, contains('SenderExternalNavigation.open'));
    expect(account, contains('SenderExternalDestination.terms'));
    expect(onboarding, contains('SenderExternalNavigation.open'));
    expect(onboarding, contains('SenderExternalDestination.terms'));
  });

  test('Stripe handoffs are explicit approved payment destinations', () {
    for (final path in [
      'lib/app/sender_mobile/sender_booking_canvas.dart',
      'lib/app/sender_mobile/gift_payment_view.dart',
      'lib/app/sender_mobile/gift_campaign_view.dart',
      'lib/app/health_plus/view/health_plus.dart',
    ]) {
      final source = read(path);
      expect(source, contains('SenderExternalNavigation.open'), reason: path);
      expect(source, contains('approvedStripePayment'), reason: path);
    }
  });
}
