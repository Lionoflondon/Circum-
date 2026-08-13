import 'dart:async';

import 'package:circum/app/sender_mobile/sender_accessibility.dart';
import 'package:circum/app/sender_mobile/sender_activity.dart';
import 'package:circum/app/sender_mobile/sender_finance.dart';
import 'package:circum/app/sender_mobile/sender_mobile_home.dart';
import 'package:circum/app/sender_mobile/sender_mobile_profile.dart';
import 'package:circum/app/sender_mobile/sender_wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_exception_guard.dart';

const _viewports = <String, Size>{
  'small phone portrait': Size(390, 844),
  'large phone portrait': Size(430, 932),
  'tablet portrait': Size(820, 1180),
  'desktop web': Size(1440, 960),
  'phone landscape': Size(844, 390),
};

class _FakeHomeRepository implements SenderHomeRepository {
  @override
  Future<SenderHomeSummary> loadSummary() async => const SenderHomeSummary(
        displayName: 'Jason Sender',
        healthProfileExists: true,
        businessAccountCount: 1,
        giftCount: 0,
        trustPoints: 74,
      );

  @override
  Future<void> markNotificationsRead(Iterable<String> ids) async {}

  @override
  Stream<List<SenderHomeNotification>> watchNotifications() =>
      Stream.value(const <SenderHomeNotification>[]);

  @override
  Stream<List<SenderHomeOrder>> watchRecentOrders() =>
      Stream.value(const <SenderHomeOrder>[]);
}

class _FakeActivityRepository implements SenderActivityRepository {
  @override
  Future<SenderActivityPage> history({String? pageToken}) async =>
      const SenderActivityPage([], null);

  @override
  Stream<List<SenderActivityItem>> watchActive() =>
      Stream.value(const <SenderActivityItem>[]);
}

class _FakeWalletRepository implements SenderWalletRepository {
  final _controller = StreamController<SenderWalletData>.broadcast();
  final bool failTransactionsAfterFirstLoad;
  int _transactionLoads = 0;

  _FakeWalletRepository({this.failTransactionsAfterFirstLoad = false});

  final wallet = SenderWalletData(
    balance: 25,
    frozen: false,
    onboardingCompleted: true,
    updatedAt: DateTime(2026, 7, 30, 12),
  );

  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<SenderSetupIntentData> createSetupIntent() async =>
      const SenderSetupIntentData(
        customerId: 'cus_test',
        ephemeralKeySecret: 'ek_test',
        setupIntentClientSecret: 'seti_test_secret',
      );

  @override
  Future<SenderSetupCheckoutSessionData> createSetupCheckoutSession() async =>
      const SenderSetupCheckoutSessionData(
        sessionId: 'cs_setup_test',
        url: 'https://checkout.stripe.com/c/pay/cs_setup_test',
      );

  @override
  Future<void> detachPaymentMethod(String paymentMethodId) async {}

  @override
  Future<SenderWalletData> initialise() async => wallet;

  @override
  Future<SenderPaymentProfile> paymentMethods() async =>
      SenderPaymentProfile.empty();

  @override
  Future<void> requestDebit({
    required double amount,
    required String relatedEntityId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> saveCheckoutPreference(
      SenderCheckoutPreference preference) async {}

  @override
  Future<void> setDefaultPaymentMethod(String paymentMethodId) async {}

  @override
  Future<SenderWalletPage> transactions({String? pageToken}) async {
    _transactionLoads += 1;
    if (failTransactionsAfterFirstLoad && _transactionLoads > 1) {
      throw StateError('transaction history unavailable');
    }
    return SenderWalletPage([
      SenderWalletTransaction(
        id: 'wallet_top_up_test',
        description: 'Roth top-up',
        direction: 'credit',
        status: 'completed',
        type: 'USER_TOP_UP',
        paymentMethodLabel: 'Stripe',
        amount: 25,
        balanceAfter: 25,
        createdAt: DateTime(2026, 7, 30, 12),
        completedAt: DateTime(2026, 7, 30, 12),
        referenceId: 'cs_test_history',
        createdBy: 'system',
        source: 'purchase',
      ),
    ], null);
  }

  @override
  Stream<SenderWalletData> watch() => _controller.stream;

  Future<void> dispose() => _controller.close();
}

class _FakeProfileRepository implements SenderMobileProfileRepository {
  final _controller = StreamController<SenderMobileProfileData>.broadcast();
  final profile = SenderMobileProfileData(
    userId: 'sender-1',
    displayName: 'Jason Sender',
    username: 'jason',
    email: 'jason@circum.app',
    phone: '+44 7700 900123',
    photoUrl: '',
    createdAt: DateTime(2026, 7, 15),
    trustScore: 84,
    trustTier: 'trusted',
    completedDeliveries: 12,
  );

  @override
  Future<void> closeAccount() async {}

  @override
  Future<SenderMobileProfileData> load() async => profile;

  @override
  Future<void> logout() async {}

  @override
  Future<SenderMobileProfileData> save({
    required String displayName,
    required String username,
    required String phone,
  }) async =>
      profile;

  @override
  Future<SenderMobileProfileData> uploadPhoto(SenderProfilePhoto photo) async =>
      profile;

  @override
  Stream<SenderMobileProfileData> watch() => _controller.stream;

  Future<void> dispose() => _controller.close();
}

class _FakeAccessibilityRepository implements SenderAccessibilityRepository {
  @override
  Future<void> save(SenderAccessibilitySettings settings) async {}

  @override
  Stream<SenderAccessibilitySettings> watch() =>
      Stream.value(const SenderAccessibilitySettings());
}

Widget _senderShell({
  required int initialIndex,
  required _FakeHomeRepository home,
  required _FakeActivityRepository activity,
  required _FakeWalletRepository wallet,
  required _FakeProfileRepository profile,
}) {
  final accessibility = SenderAccessibilityController(
    repository: _FakeAccessibilityRepository(),
  )..start();
  return MaterialApp(
    home: SenderAccessibilityScope(
      controller: accessibility,
      child: SenderMobileHome(
        initialAuthenticated: true,
        initialIndex: initialIndex,
        homeRepository: home,
        activityRepository: activity,
        walletRepository: wallet,
        profileRepository: profile,
        sendTabBuilder: (_) => const SizedBox.expand(
          child: Center(
            child: Text('Where are we collecting from?'),
          ),
        ),
      ),
    ),
  );
}

Future<Rect> _tabRootRect(
  WidgetTester tester, {
  required int index,
  required Size size,
}) async {
  final wallet = _FakeWalletRepository();
  final profile = _FakeProfileRepository();
  addTearDown(wallet.dispose);
  addTearDown(profile.dispose);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await pumpSenderFrame(
    tester,
    _senderShell(
      initialIndex: index,
      home: _FakeHomeRepository(),
      activity: _FakeActivityRepository(),
      wallet: wallet,
      profile: profile,
    ),
    size: size,
  );

  return tester.getRect(find.byKey(ValueKey<String>('sender-tab-$index')));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final MapEntry(key: viewportName, value: size) in _viewports.entries) {
    for (final tab in const [
      (index: 0, label: 'Home', content: 'Health+'),
      (index: 1, label: 'Send', content: 'Where are we collecting from?'),
      (index: 2, label: 'Activity', content: 'Activity'),
      (index: 3, label: 'Wallet', content: 'Wallet'),
      (index: 4, label: 'Profile', content: 'Jason Sender'),
    ]) {
      testWidgets(
        'Sender ${tab.label} renders first frame with no layout exceptions on $viewportName',
        (tester) async {
          final wallet = _FakeWalletRepository();
          final profile = _FakeProfileRepository();
          addTearDown(wallet.dispose);
          addTearDown(profile.dispose);

          await expectNoFlutterLayoutExceptions(tester, () async {
            await pumpSenderFrame(
              tester,
              _senderShell(
                initialIndex: tab.index,
                home: _FakeHomeRepository(),
                activity: _FakeActivityRepository(),
                wallet: wallet,
                profile: profile,
              ),
              size: size,
            );
          });

          expect(find.text(tab.content), findsAtLeastNWidgets(1));
          for (final label in senderMobileBottomNavigationLabels) {
            expect(find.text(label), findsAtLeastNWidgets(1));
          }
        },
      );
    }
  }

  testWidgets('Sender bottom navigation remains functional under layout guard',
      (tester) async {
    final wallet = _FakeWalletRepository();
    final profile = _FakeProfileRepository();
    addTearDown(wallet.dispose);
    addTearDown(profile.dispose);

    await expectNoFlutterLayoutExceptions(tester, () async {
      await pumpSenderFrame(
        tester,
        _senderShell(
          initialIndex: 0,
          home: _FakeHomeRepository(),
          activity: _FakeActivityRepository(),
          wallet: wallet,
          profile: profile,
        ),
        size: _viewports['large phone portrait']!,
      );
      await tester.tap(find.text('Wallet').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    });

    expect(find.text('Available Roth'), findsOneWidget);
  });

  testWidgets('Wallet keeps visible transaction history when refresh fails',
      (tester) async {
    final wallet = _FakeWalletRepository(failTransactionsAfterFirstLoad: true);
    final profile = _FakeProfileRepository();
    addTearDown(wallet.dispose);
    addTearDown(profile.dispose);

    await pumpSenderFrame(
      tester,
      _senderShell(
        initialIndex: 3,
        home: _FakeHomeRepository(),
        activity: _FakeActivityRepository(),
        wallet: wallet,
        profile: profile,
      ),
      size: _viewports['large phone portrait']!,
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Roth top-up'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Roth top-up'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Wallet'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 300),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.scrollUntilVisible(
      find.text('Roth top-up'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Roth top-up'), findsOneWidget);
    expect(find.textContaining('No Roth activity yet'), findsNothing);
  });

  for (final MapEntry(key: viewportName, value: size) in _viewports.entries) {
    testWidgets(
      'Sender primary tabs share one body viewport on $viewportName',
      (tester) async {
        final rects = <String, Rect>{};
        for (final tab in const [
          (index: 0, label: 'Home'),
          (index: 1, label: 'Send'),
          (index: 2, label: 'Activity'),
          (index: 3, label: 'Wallet'),
          (index: 4, label: 'Profile'),
        ]) {
          rects[tab.label] = await _tabRootRect(
            tester,
            index: tab.index,
            size: size,
          );
        }

        final send = rects['Send']!;
        for (final MapEntry(key: label, value: rect) in rects.entries) {
          expect(
            rect,
            equals(send),
            reason:
                '$label diverged from the canonical Send tab body viewport.',
          );
        }
      },
    );
  }
}
