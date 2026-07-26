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
    final canonicalHomeBuild = canonicalHome.substring(
      canonicalHome.indexOf('Widget build(BuildContext context)'),
    );

    for (final marker in const [
      "Key('sender-home-canonical-content')",
      'Send a parcel',
      'Send now',
      'Track delivery',
      '_RebuiltSenderHomeHeader',
      '_RebuiltSenderHomeHero',
      '_RebuiltSenderServicesGrid',
      '_RebuiltSenderRecentActivity',
      '_RebuiltSenderNotificationStrip',
      'Your Circum',
      'Health+',
      'Business',
      'Gifts',
      'Recent Activity',
      'No deliveries yet',
      'Your completed deliveries will appear here.',
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
      'Where are we sending today?',
      'Quick services',
      'Send Parcel',
      'Important updates',
    ]) {
      expect(canonicalHomeBuild, isNot(contains(forbidden)));
    }
  });

  test('Sender web deep link opens the canonical Gifts flow', () {
    final preview = read('lib/app/sender_mobile/sender_mobile_preview.dart');
    final home = read('lib/app/sender_mobile/sender_mobile_home.dart');

    expect(preview, contains('String? _initialSenderRouteName(Uri uri)'));
    expect(preview, contains('initialRoute: Navigator.defaultRouteName'));
    expect(
        preview, contains('routes: {Navigator.defaultRouteName: (_) => home}'));
    expect(preview, contains('onGenerateInitialRoutes: (_) => ['));
    expect(preview, contains('fragment == GiftModeView.routeName'));
    expect(preview, contains('initialRouteName: initialRouteName'));
    expect(home, contains('final String? initialRouteName;'));
    expect(home, contains('void _openInitialSenderRoute()'));
    expect(home, contains('case GiftModeView.routeName:'));
    expect(home, contains('builder: (_) => const GiftModeView()'));
  });

  test('Sender send flow remains the canonical mobile booking canvas', () {
    final canvas = read('lib/app/sender_mobile/sender_booking_canvas.dart');
    final state = read('lib/app/sender_mobile/sender_booking_state.dart');
    final bloc = read('lib/app/send_package/bloc/send_package_bloc.dart');

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

    expect(canvas, contains('_backendDraftRestoreTimeout'));
    expect(canvas, contains('_localDraftRestoreTimeout'));
    expect(canvas, contains('.timeout('));
    expect(canvas, contains('finally'));
    expect(canvas, contains('_clearQueuedLocalDraft();'));
    expect(canvas, contains("Your previous draft couldn't be restored."));

    final activeStatuses = RegExp(
      r'static const Set<String> _activeRequestStatuses = \{([\s\S]*?)\};',
    ).firstMatch(bloc)?.group(1);
    expect(activeStatuses, isNotNull);
    for (final terminalStatus in const [
      'cancelled',
      'canceled',
      'cancelled_verified_discrepancy',
      'sender_no_show_pickup',
    ]) {
      expect(activeStatuses, isNot(contains("'$terminalStatus'")));
    }
    expect(bloc, contains('_clearActiveRequestIfCurrent'));
    expect(bloc, contains('_terminalRequestStatuses'));
  });

  test('Sender billing weight uses the higher of customer and IRIS weight', () {
    final bloc = read('lib/app/send_package/bloc/send_package_bloc.dart');
    final handlerStart = bloc.indexOf('void _handleSetParcelWeight(');
    final handlerEnd =
        bloc.indexOf('void _handleRequestCanonicalIrisEstimate', handlerStart);
    expect(handlerStart, isNonNegative);
    expect(handlerEnd, greaterThan(handlerStart));

    final handler = bloc.substring(handlerStart, handlerEnd);
    final trustedStart =
        handler.indexOf('final trusted = await IrisLearningBridge');
    final emitStart = handler.indexOf('emit(', trustedStart);
    expect(trustedStart, isNonNegative);
    expect(emitStart, greaterThan(trustedStart));
    final trustedResolution = handler.substring(trustedStart, emitStart);

    expect(
        trustedResolution, contains('DeliveryPricing.checkoutPricingWeightKg'));
    expect(trustedResolution, contains('userEnteredWeightKg: event.weightKg'));
    expect(
      trustedResolution,
      contains('irisEstimatedWeightKg: trusted.pricingWeightKg'),
      reason:
          'Billing must use whichever is higher: customer-declared weight or IRIS weight.',
    );
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
