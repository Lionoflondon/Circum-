import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String source;
  late final String requestWithdrawalBody;

  setUpAll(() {
    source = File('lib/web_sender_app.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _requestWithdrawal() async {');
    final end = source.indexOf('String _withdrawalErrorMessage', start);
    expect(start, isNonNegative);
    expect(end, isNonNegative);
    requestWithdrawalBody = source.substring(start, end);
  });

  test('Rider payout request uses backend callable', () {
    expect(requestWithdrawalBody, contains("httpsCallable('requestRiderWithdrawal')"));
    expect(requestWithdrawalBody, contains("'amount': amount"));
  });

  test('Rider payout request has no direct Firestore fallback writes', () {
    expect(requestWithdrawalBody, isNot(contains("collection('payoutRequests')")));
    expect(requestWithdrawalBody, isNot(contains("collection('riderEarnings')")));
    expect(requestWithdrawalBody, isNot(contains('db.batch()')));
    expect(requestWithdrawalBody, isNot(contains('batch.set')));
    expect(requestWithdrawalBody, isNot(contains('FieldValue.increment')));
  });

  test('Rider payout request maps callable failures for the user', () {
    expect(source, contains("case 'unauthenticated':"));
    expect(source, contains("case 'already-exists':"));
    expect(source, contains("case 'failed-precondition':"));
    expect(source, contains("case 'permission-denied':"));
    expect(source, contains("case 'resource-exhausted':"));
  });
}
