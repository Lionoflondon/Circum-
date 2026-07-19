import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const forbiddenDestinations = [
    'LegacyHome',
    'PlaceholderHome',
    'EmptyHome',
    'AnimatedHome',
    'FallbackHome',
    'AccountDetails',
    'BusinessWallet',
    'AdminWallet',
    'LegacyFinance',
    'WebWallet',
    'GoRouter',
    'AutoRoute',
    'Beamer',
    'context.go',
    'context.push',
    'pushNamed',
  ];

  String read(String path) => File(path).readAsStringSync();

  test('bottom navigation resolves to canonical Sender tab widgets', () {
    final source = read('lib/app/sender_mobile/sender_mobile_home.dart');

    expect(source, contains("const senderMobileBottomNavigationLabels = ["));
    for (final label in const [
      "'Home'",
      "'Send'",
      "'Activity'",
      "'Wallet'",
      "'Profile'",
    ]) {
      expect(source, contains(label));
    }

    expect(source, contains('child: _selectedAppTab()'));
    expect(source, isNot(contains('return IndexedStack(')));
    expect(source, contains('_CanonicalSenderHome('));
    expect(source, isNot(contains('_SenderStableHomeSurface(')));
    expect(source, contains('const SenderBookingCanvas()'));
    expect(source, contains('SenderActivityView('));
    expect(source, contains('const SenderWalletView()'));
    expect(source, contains('SenderMobileProfileView('));

    final selectedTabs =
        source.substring(source.indexOf('Widget _selectedAppTab()'));
    final homeIndex = selectedTabs.indexOf('_CanonicalSenderHome(');
    final sendIndex = selectedTabs.indexOf('const SenderBookingCanvas()');
    final activityIndex = selectedTabs.indexOf('SenderActivityView(');
    final walletIndex = selectedTabs.indexOf('const SenderWalletView()');
    final profileIndex = selectedTabs.indexOf('SenderMobileProfileView(');

    expect(homeIndex, greaterThan(0));
    expect(sendIndex, greaterThan(homeIndex));
    expect(activityIndex, greaterThan(sendIndex));
    expect(walletIndex, greaterThan(activityIndex));
    expect(profileIndex, greaterThan(walletIndex));
  });

  test('Sender app surface is forced to occupy the visible viewport', () {
    final source = read('lib/app/sender_mobile/sender_mobile_home.dart');

    expect(source, contains('Positioned.fill('));
    expect(source, contains('SizedBox.expand(child: _activeSurface())'));
    expect(source, contains("key: const Key('sender-home-canonical-content')"));
  });

  test('Sender Home contains the canonical premium consumer sections', () {
    final source = read('lib/app/sender_mobile/sender_mobile_home.dart');
    final canonicalHome = source.substring(
      source.indexOf('class _CanonicalSenderHome'),
      source.indexOf('class _SenderDashboard'),
    );

    for (final marker in const [
      "Key('sender-home-canonical-content')",
      'Where are we sending today?',
      'Track Delivery',
      'Send Parcel',
      'Quick services',
      'Health+',
      'Business',
      'Gifts',
      'SenderWalletHomeSummary',
      'Activity',
      'Trust',
      'Important updates',
    ]) {
      expect(canonicalHome, contains(marker));
    }

    for (final forbidden in const [
      '_SenderStableHomeSurface',
      '_StableHomePrimaryCard',
      '_StableHomeActionGrid',
      '_StableHomeInfoCard',
      'Ready when you are.',
      'Send something',
    ]) {
      expect(canonicalHome, isNot(contains(forbidden)));
    }
  });

  test('Sender send flow remains the canonical mobile booking canvas', () {
    final canvas = read('lib/app/sender_mobile/sender_booking_canvas.dart');
    final state = read('lib/app/sender_mobile/sender_booking_state.dart');

    for (final step in const [
      'pickup',
      'dropoff',
      'recipient',
      'deliveryTime',
      'parcel',
      'iris',
      'options',
      'review',
      'payment',
      'findingRider',
      'liveTracking',
    ]) {
      expect(state, contains(step));
      expect(canvas, contains('SenderBookingStep.$step'));
    }

    for (final label in const [
      'Pickup',
      'Drop-off',
      'Recipient',
      'Confirm delivery time',
      'Tell us about your parcel.',
      'IRIS has estimated your parcel.',
      'Choose options',
      'Review delivery',
      'Continue to payment',
      'Track your delivery.',
    ]) {
      expect('$canvas\n$state', contains(label));
    }

    for (final forbidden in const [
      'lib/website',
      'admin_phase1_shell',
      'Admin',
      'Legacy',
      'Experimental',
    ]) {
      expect(canvas, isNot(contains(forbidden)));
    }
  });

  test('Sender wallet actions stay inside Sender wallet destinations', () {
    final source = read('lib/app/sender_mobile/sender_wallet.dart');

    for (final destination in const [
      '_ManagePaymentsScreen',
      '_TransactionDetailsScreen',
      '_WalletActivityScreen',
      '_WalletInformationScreen',
      '_WalletSupportScreen',
      'SenderReferralScreen',
    ]) {
      expect(source, contains(destination));
    }

    for (final forbidden in const [
      'BusinessWallet',
      'AdminWallet',
      'LegacyFinance',
      'WebWallet',
      'lib/website',
      'admin_phase1_shell',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
  });

  test('Sender profile actions resolve to canonical Sender destinations', () {
    final source = read('lib/app/sender_mobile/sender_mobile_profile.dart');

    for (final destination in const [
      'SenderNotificationsView',
      'RideChatPageView',
      '_SenderClosedSubmissionScreen',
      '_SenderSecuritySettingsScreen',
      '_SenderLanguageSettingsScreen',
      '_SenderAccessibilitySettingsScreen',
      '_SenderLegalDocumentScreen',
      'SenderReferralScreen',
    ]) {
      expect(source, contains(destination));
    }

    expect(source, contains("title: 'Help Shape Circum'"));
    expect(source, contains("title: 'Community Requests'"));
    expect(source, contains('closeImmediately'));
    expect(source, contains('initialMessage'));
    expect(source, contains('Message:'));
    expect(source, contains('not trackable in-app'));
    expect(source, isNot(contains('Track Circum community requests')));
    expect(
        source, contains("key: const Key('sender-profile-help-shape-circum')"));
    expect(source,
        contains("key: const Key('sender-profile-community-requests')"));

    for (final forbidden in forbiddenDestinations) {
      expect(source, isNot(contains(forbidden)));
    }
  });

  test('Sender mobile sources do not import cross-product UI destinations', () {
    final senderFiles = Directory('lib/app/sender_mobile')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in senderFiles) {
      final source = file.readAsStringSync();
      for (final forbiddenImport in const [
        "import '../../website/",
        "import '../admin/",
        "import '../../admin/",
        "import '../website/",
        "import 'package:circum_rider",
        'Circum-Rider',
      ]) {
        expect(
          source,
          isNot(contains(forbiddenImport)),
          reason: '${file.path} imports a forbidden product surface.',
        );
      }
    }
  });
}
