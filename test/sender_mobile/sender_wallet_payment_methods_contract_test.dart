import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final walletSource = File('lib/app/sender_mobile/sender_wallet.dart');
  final financeSource = File('lib/app/sender_mobile/sender_finance.dart');

  test('Sender Wallet payment method actions are bounded and retryable', () {
    final source = walletSource.readAsStringSync();

    expect(source, contains('static const _firebaseReadTimeout'));
    expect(source, contains("httpsCallable('listSenderPaymentMethods')"));
    expect(source, contains("httpsCallable('createSenderSetupIntent')"));
    expect(source, contains("httpsCallable('detachSenderPaymentMethod')"));
    expect(source, contains("httpsCallable('setDefaultSenderPaymentMethod')"));
    expect(source, contains("httpsCallable('saveSenderCheckoutPreference')"));
    expect(source, contains('.timeout(_firebaseReadTimeout)'));
    expect(source, contains('.timeout(_senderWalletOperationTimeout)'));
    expect(source, contains('Payment setup is taking too long. Try again.'));
    expect(source, contains('Card removal timed out. Try again.'));
    expect(source, contains('Payment method removed.'));
  });

  test('shared Sender payment profile repository bounds callable waits', () {
    final source = financeSource.readAsStringSync();

    expect(source, contains("import 'dart:async';"));
    expect(source, contains('static const _operationTimeout'));
    expect(source, contains("httpsCallable('listSenderPaymentMethods')"));
    expect(source, contains("httpsCallable('createSenderSetupIntent')"));
    expect(source, contains("httpsCallable('detachSenderPaymentMethod')"));
    expect(source, contains("httpsCallable('setDefaultSenderPaymentMethod')"));
    expect(source, contains("httpsCallable('saveSenderCheckoutPreference')"));
    expect(source, contains('.timeout(_operationTimeout)'));
  });
}
