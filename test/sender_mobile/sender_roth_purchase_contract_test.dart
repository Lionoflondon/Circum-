import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender Wallet exposes backend-authorized Roth purchase', () {
    final source =
        File('lib/app/sender_mobile/sender_wallet.dart').readAsStringSync();

    expect(source, contains("httpsCallable('createWalletTopUp')"));
    expect(source, contains("title: 'Buy Roth'"));
    expect(source, contains("checkoutUrl.scheme != 'https'"));
    expect(source, contains("webOnlyWindowName: kIsWeb ? '_self' : null"));
    expect(source, isNot(contains('rothCredit: amount')));
    expect(source, isNot(contains("collection('senderWallets').doc")));
  });

  test('Sender release retains Business and Roth together', () {
    final home = File('lib/app/sender_mobile/sender_mobile_home.dart')
        .readAsStringSync();
    final routing = File('lib/web_platform_routing.dart').readAsStringSync();
    final wallet =
        File('lib/app/sender_mobile/sender_wallet.dart').readAsStringSync();

    expect(home, contains("import '../business/business_access_view.dart';"));
    expect(home, contains('BusinessAccessView'));
    expect(routing, contains("canonicalPath: '/send/business'"));
    expect(wallet, contains("title: 'Buy Roth'"));
    expect(wallet, contains("httpsCallable('createWalletTopUp')"));
  });
}
