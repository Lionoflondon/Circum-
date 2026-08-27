import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender host keeps production viewport sizing unlocked', () {
    final index = File('web/index.html').readAsStringSync();

    expect(index, contains('min-height: 100%;'));
    expect(index, isNot(contains('overflow: hidden;')));
    expect(index, isNot(contains('flutter-view,')));
    expect(index, isNot(contains('flt-glass-pane')));
  });

  test('Sender app cannot enter app shell without Firebase Auth authority', () {
    final preview = File('lib/app/sender_mobile/sender_mobile_preview.dart')
        .readAsStringSync();
    final app = File('lib/app.dart').readAsStringSync();
    final appNav =
        File('lib/app/bottom_nav/view/app_nav.dart').readAsStringSync();

    expect(preview, contains('initialAuthenticated: false'));
    expect(preview, contains('previewAuthEnabled: true'));
    expect(preview, isNot(contains('initialAuthenticated: true')));
    expect(preview, isNot(contains('previewAuthEnabled: false')));
    expect(app, isNot(contains('initialAuthenticated: true')));
    expect(app, contains('SenderMobileHome(previewAuthEnabled: true)'));
    expect(appNav, isNot(contains('initialAuthenticated: true')));
    expect(appNav, contains('SenderMobileHome(previewAuthEnabled: true)'));
  });

  test('Sender startup has a visible recovery boundary before runApp', () {
    final main = File('lib/main.dart').readAsStringSync();
    final startup =
        File('lib/app/sender_mobile/sender_startup.dart').readAsStringSync();

    expect(main, contains('runSenderStartup('));
    expect(startup, contains('renderRecovery();'));
    expect(startup, contains('catch (_)'));
    expect(startup, contains("timeout(const Duration(seconds: 20))"));
  });

  test('Sender unresolved startup does not reuse the branded splash', () {
    final app = File('lib/app.dart').readAsStringSync();

    expect(app, contains('case AppState.unknownSessionState:'));
    expect(app, contains('return const _SenderBootSurface();'));
    expect(app, isNot(contains('return const IndexPage();')));
    expect(app, isNot(contains('assets/images/splash.png')));
    expect(app, isNot(contains("authentication/view/index_page.dart")));
    expect(app, contains('class _SenderBootSurface'));
  });

  test('Sender App Check activation is bounded on every platform', () {
    final source =
        File('lib/app/security/circum_app_check.dart').readAsStringSync();
    expect(source, contains('activation.timeout(const Duration(seconds: 5))'));
    expect(source, contains('on TimeoutException'));
  });

  test('Sender session restore never signs out existing users by account age',
      () {
    final authBloc =
        File('lib/app/authentication/bloc/auth_bloc.dart').readAsStringSync();
    final handler = authBloc.substring(
      authBloc.indexOf('Future<void> _handleSortSessionState'),
      authBloc.indexOf('void _handleResetStatus'),
    );

    expect(handler, isNot(contains('metadata.creationTime')));
    expect(handler, isNot(contains('authChangeDate')));
    expect(handler, isNot(contains('add(SignOut())')));
  });

  test('Home, Wallet and Profile stay free of the booking route backdrop', () {
    final home = File('lib/app/sender_mobile/sender_mobile_home.dart')
        .readAsStringSync();

    expect(home, isNot(contains('_SenderMapBackdrop(active: false)')));
    expect(home, contains('case 0:'));
    expect(home, contains('case 3:'));
    expect(home, contains('case 4:'));
    expect(home, contains('SenderWalletView'));
    expect(home, contains('SenderMobileProfileView'));
  });

  test('Sender wallet is cache-first and never waits indefinitely', () {
    final wallet =
        File('lib/app/sender_mobile/sender_wallet.dart').readAsStringSync();

    expect(wallet, contains('_loadCachedSnapshot()'));
    expect(wallet, contains('_walletOperationTimeout'));
    expect(wallet, contains('_firebaseReadTimeout'));
    expect(wallet, contains('operation.timeout(_walletOperationTimeout)'));
    expect(
      wallet,
      contains(RegExp(r'\.call\(\)\s*\.timeout\(_firebaseReadTimeout\)')),
    );
    expect(
      wallet,
      contains(RegExp(r'\.get\(\)\s*\.timeout\(_firebaseReadTimeout\)')),
    );
    expect(
        wallet, contains("profile?.data['senderWalletOnboardingCompleted']"));
    expect(wallet, contains('_wallet ??= const SenderWalletData'));
    expect(wallet, contains('_scheduleWalletRetry'));
    expect(wallet,
        isNot(contains('if (wallet == null || profile == null) return;')));
    expect(wallet, isNot(contains('controller.addError')));
  });

  test('Sender wallet shell does not nest vertical scroll views', () {
    final wallet =
        File('lib/app/sender_mobile/sender_wallet.dart').readAsStringSync();
    final shellStart = wallet.indexOf('class _WalletPageShell');
    final shellEnd = wallet.indexOf('class _AvailableRothCard');
    final shell = wallet.substring(shellStart, shellEnd);

    expect(shell, contains('return SenderPrimaryPageShell('));
    expect(shell, contains('child: child'));
    expect(shell, isNot(contains('return ListView(')));
    expect(
      shell,
      isNot(contains('children: [')),
      reason:
          'The Wallet page content already owns the RefreshIndicator/ListView. '
          'Adding a second vertical ListView gives the inner viewport unbounded '
          'height and can render only the background.',
    );
  });

  test('Sender page shell and bottom navigation do not scale the app', () {
    final shell =
        File('lib/app/sender_mobile/sender_page_shell.dart').readAsStringSync();
    final home = File('lib/app/sender_mobile/sender_mobile_home.dart')
        .readAsStringSync();
    final bottomNavStart = home.indexOf('class _SenderBottomNav');
    final bottomNavEnd = home.indexOf('class _SenderAvatar');
    final bottomNav = home.substring(bottomNavStart, bottomNavEnd);

    for (final source in [shell, bottomNav]) {
      expect(source, isNot(contains('Transform.scale')));
      expect(source, isNot(contains('AnimatedScale')));
      expect(source, isNot(contains('FittedBox')));
      expect(source, isNot(contains('FractionallySizedBox')));
      expect(source, isNot(contains('textScaleFactor')));
      expect(source, isNot(contains('textScaler')));
    }
  });

  test('Sender booking tab does not introduce a nested Scaffold', () {
    final booking = File('lib/app/sender_mobile/sender_booking_canvas.dart')
        .readAsStringSync();

    expect(booking, isNot(contains(RegExp(r'\breturn\s+Scaffold\('))));
    expect(booking, isNot(contains(RegExp(r'\breturn\s+const\s+Scaffold\('))));
    expect(booking, contains('return ColoredBox('));
  });
}
