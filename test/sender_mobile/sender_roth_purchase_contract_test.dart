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
}
