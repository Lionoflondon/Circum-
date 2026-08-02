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
    expect(source,
        contains('SenderWalletView(repository: widget.walletRepository)'));
    expect(source, contains('SenderMobileProfileView('));

    final selectedTabs =
        source.substring(source.indexOf('Widget _selectedAppTab()'));
    final homeIndex = selectedTabs.indexOf('_CanonicalSenderHome(');
    final sendIndex = selectedTabs.indexOf('const SenderBookingCanvas()');
    final activityIndex = selectedTabs.indexOf('SenderActivityView(');
    final walletIndex = selectedTabs.indexOf('SenderWalletView(');
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
      'Choose your delivery options.',
      'Review your delivery.',
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

  test(
      'Sender IRIS requests timeout and stale matches require non-empty item text',
      () {
    final bloc = read('lib/app/send_package/bloc/send_package_bloc.dart');
    final canvas = read('lib/app/sender_mobile/sender_booking_canvas.dart');

    final handlerStart =
        bloc.indexOf('void _handleRequestCanonicalIrisEstimate');
    final handlerEnd = bloc.indexOf('double _numFrom', handlerStart);
    expect(handlerStart, isNonNegative);
    expect(handlerEnd, greaterThan(handlerStart));
    final handler = bloc.substring(handlerStart, handlerEnd);
    expect(handler, contains("httpsCallable('analyseIris')"));
    expect(handler, contains('.timeout(const Duration(seconds: 15))'));

    final matchStart = canvas.indexOf('bool _irisMatchesParcel');
    final matchEnd =
        canvas.indexOf('String _irisEstimatedWeightDisplay', matchStart);
    expect(matchStart, isNonNegative);
    expect(matchEnd, greaterThan(matchStart));
    final matcher = canvas.substring(matchStart, matchEnd);
    expect(matcher, contains('final item = itemName.trim().toLowerCase();'));
    expect(matcher, contains('item.isNotEmpty && actual.contains(item)'));
  });

  test('Sender async IRIS and quote refreshes clear stale booking state first',
      () {
    final bloc = read('lib/app/send_package/bloc/send_package_bloc.dart');
    final state = read('lib/app/send_package/bloc/send_package_state.dart');

    for (final clearFlag in const [
      'clearCanonicalIrisResult',
      'clearSenderQuoteId',
      'clearSenderQuoteTotal',
      'clearSenderQuoteSpeed',
      'clearSenderPaymentSession',
      'clearSenderPaymentStatus',
      'clearSenderPaymentClientSecret',
      'clearSenderPaymentIntent',
      'clearSenderPaymentCustomer',
      'clearSenderPaymentEphemeralKey',
      'clearSenderPaymentCheckoutUrl',
      'clearSenderCreatedRequest',
    ]) {
      expect(state, contains(clearFlag));
      expect(bloc, contains('$clearFlag: true'));
    }
    expect(state, contains('clearItemDescription'));
    expect(
      bloc,
      contains('clearItemDescription: itemDescription.trim().isEmpty'),
    );

    final irisStart = bloc.indexOf('void _handleRequestCanonicalIrisEstimate');
    final irisCallable =
        bloc.indexOf("httpsCallable('analyseIris')", irisStart);
    expect(irisStart, isNonNegative);
    expect(irisCallable, greaterThan(irisStart));
    final irisPreflight = bloc.substring(irisStart, irisCallable);
    expect(irisPreflight, contains('_clearIrisDependentState'));
    expect(irisPreflight, contains('Stopwatch()..start()'));

    final quoteStart = bloc.indexOf('void _handleRequestSenderBookingQuote');
    final quoteCallable =
        bloc.indexOf("_callableMap('createSenderBookingQuote'", quoteStart);
    expect(quoteStart, isNonNegative);
    expect(quoteCallable, greaterThan(quoteStart));
    final quotePreflight = bloc.substring(quoteStart, quoteCallable);
    expect(quotePreflight, contains('clearSenderQuoteId: true'));
    expect(quotePreflight, contains('clearSenderQuoteTotal: true'));
    expect(quotePreflight, contains('clearSenderPaymentSession: true'));
    expect(quotePreflight, contains('clearSenderCreatedRequest: true'));
  });

  test('Sender parcel edits and photo removal clear stale IRIS state', () {
    final canvas = read('lib/app/sender_mobile/sender_booking_canvas.dart');
    final bloc = read('lib/app/send_package/bloc/send_package_bloc.dart');

    final removeStart = canvas.indexOf('void _removeParcelPhoto()');
    final restoreStart = canvas.indexOf('void _restoreRouteFromDraftIfReady');
    expect(removeStart, isNonNegative);
    expect(restoreStart, greaterThan(removeStart));
    final removeHandler = canvas.substring(removeStart, restoreStart);
    expect(removeHandler, contains('const ClearIrisParcelState()'));
    expect(removeHandler, contains('_lastBackendQuoteKey = null'));

    final parcelChangeStart = canvas.indexOf('void _onParcelChanged()');
    final photoPickerStart = canvas.indexOf('Future<void> _pickParcelPhoto()');
    expect(parcelChangeStart, isNonNegative);
    expect(photoPickerStart, greaterThan(parcelChangeStart));
    final parcelChangeHandler =
        canvas.substring(parcelChangeStart, photoPickerStart);
    expect(parcelChangeHandler, contains('engine.canonicalIrisResult != null'));
    expect(parcelChangeHandler, contains('engine.irisResult != null'));
    expect(parcelChangeHandler, contains('engine.senderQuoteId != null'));
    expect(parcelChangeHandler, contains('const ClearIrisParcelState()'));

    final resetStart =
        bloc.indexOf('SendPackageState _clearIrisDependentState');
    final clearStart = bloc.indexOf('void _handleClearIrisParcelState');
    final reviewStart = bloc.indexOf('String _weightReviewMessage', clearStart);
    expect(resetStart, isNonNegative);
    expect(clearStart, greaterThan(resetStart));
    expect(reviewStart, greaterThan(clearStart));
    final resetHelper = bloc.substring(resetStart, clearStart);
    final clearHandler = bloc.substring(clearStart, reviewStart);
    expect(clearHandler, contains('_clearIrisDependentState(state)'));
    expect(resetHelper, contains('parcelWeightKg: 0'));
    expect(resetHelper, contains('price: 0'));
    expect(resetHelper, contains('clearIrisResult: true'));
    expect(resetHelper, contains('clearCanonicalIrisResult: true'));
    expect(resetHelper, contains('clearSenderQuoteId: true'));
    expect(resetHelper, contains('clearSenderPaymentSession: true'));
    expect(resetHelper, contains('clearSenderPaymentStatus: true'));
    expect(resetHelper, contains('senderPaymentError:'));
    expect(resetHelper, contains('senderDeliveryError:'));
  });

  test('Sender nullable booking artifacts are never cleared with null literals',
      () {
    final source = read('lib/app/send_package/bloc/send_package_bloc.dart');

    for (final staleClear in const [
      'canonicalIrisResult: null',
      'itemDescription: null',
      'senderQuoteId: null',
      'senderQuoteTotal: null',
      'senderQuoteSpeed: null',
      'senderPaymentSessionId: null',
      'senderPaymentClientSecret: null',
      'senderPaymentIntentId: null',
      'senderPaymentCustomerId: null',
      'senderPaymentEphemeralKeySecret: null',
      'senderPaymentCheckoutUrl: null',
      'senderCreatedRequestId: null',
    ]) {
      expect(
        source,
        isNot(contains(staleClear)),
        reason:
            '$staleClear does not clear copyWith state; use the explicit clear flag.',
      );
    }
  });

  test('Sender address search is backend-mediated and bounded by timeout', () {
    final source = read('lib/app/send_package/repo/place_api.dart');

    expect(source, contains("httpsCallable('searchFreeUkAddresses')"));
    expect(source, contains("httpsCallable('resolveUkAddressPlace')"));
    expect(source, contains("'sessionToken': '\$sessionToken'"));
    expect(source, contains(".timeout(const Duration(seconds: 8))"));
    expect(source, isNot(contains('maps.googleapis.com')));
  });

  test('Sender-facing delivery models never expose Rider phone fallbacks', () {
    final profile = read('lib/app/sender_profile/sender_profile.dart');
    final deliveryData =
        read('lib/app/send_package/models/delivery_data.m.dart');

    expect(profile, contains('assignedDriverPhone: \'\','));
    expect(deliveryData, contains('phoneNumber: \'\','));
    expect(profile, isNot(contains("data['riderPhone']")));
    expect(profile, isNot(contains("data['driverPhone']")));
    expect(profile, isNot(contains("data['courierPhone']")));
    expect(deliveryData, isNot(contains("data['riderPhone']")));
    expect(deliveryData, isNot(contains("data['phoneNumber']")));
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
