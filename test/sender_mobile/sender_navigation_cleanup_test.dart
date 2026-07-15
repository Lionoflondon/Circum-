import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authenticated sessions use the canonical Sender navigation tree', () {
    final app = File('lib/app.dart').readAsStringSync();
    final senderHome = File('lib/app/sender_mobile/sender_mobile_home.dart')
        .readAsStringSync();

    expect(
      app,
      contains('return const SenderMobileHome(initialAuthenticated: true);'),
    );
    expect(app, isNot(contains('NavbarBloc')));
    expect(app, isNot(contains('AppNavView')));
    expect(senderHome, contains('senderMobileBottomNavigationLabels'));
    expect(senderHome, contains('const SenderBookingCanvas()'));
    expect(senderHome, contains('SenderActivityView('));
    expect(senderHome, contains('const SenderWalletView()'));
    expect(senderHome, contains('SenderMobileProfileView('));
  });

  test('retired navigation and placeholder screens stay removed', () {
    const retiredPaths = [
      'lib/app/bottom_nav/view/app_nav.dart',
      'lib/app/bottom_nav/bloc/navbar_bloc.dart',
      'lib/app/send_package/view/home.dart',
      'lib/app/send_package/view/circum_select.dart',
      'lib/app/send_package/view/parts/active_delivery_details.dart',
    ];

    for (final path in retiredPaths) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }

    final gifts = File('lib/app/sender_mobile/gift_relationship_view.dart')
        .readAsStringSync();
    final web = File('lib/web_sender_app.dart').readAsStringSync();
    expect(gifts, isNot(contains('GiftJourneyPlaceholderView')));
    expect(web, isNot(contains('_GiftsComingSoonPage')));
  });
}
