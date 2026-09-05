import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../lib/app/authentication/sender_signup_referral.dart';

void main() {
  test(
      'join link survives as a normalized signup prefill and malformed link is safe',
      () {
    expect(signupReferralFromRoute('/join/a%20b-12'), 'AB12');
    expect(signupReferralFromRoute('/join/%ZZ'), '');
    expect(signupReferralFromRoute('https://circumuk.com/#/join/ab12'), 'AB12');
  });
  test('normalization is optional, strips hidden spaces and bounds codes', () {
    expect(normalizeSignupReferral(' a b-12_\u200B '), 'AB12');
    expect(normalizeSignupReferral(''), '');
    expect(normalizeSignupReferral('A' * 30), 'A' * 24);
  });
  test('every backend outcome is visible and failure never throws', () async {
    for (final status in [
      'applied',
      'already_attached',
      'rejected_self_referral',
      'not_found',
      'invalid',
      'unknown'
    ]) {
      expect(
          await applySignupReferral(' abc ', (code) async {
            expect(code, 'ABC');
            return {'status': status};
          }),
          referralSignupMessage(status));
    }
    expect(
        await applySignupReferral('', (_) => throw StateError('must not call')),
        'Account created.');
    expect(
        await applySignupReferral(
            'abc', (_) async => throw StateError('network')),
        referralSignupMessage('unknown'));
    expect(
        await applySignupReferral('abc', (_) => Completer<dynamic>().future,
            timeout: const Duration(milliseconds: 1)),
        referralSignupMessage('timeout'));
    for (final code in [
      'deadline-exceeded',
      'unavailable',
      'not-found',
      'invalid-argument'
    ]) {
      final message = await applySignupReferral(
          'abc',
          (_) async =>
              throw FirebaseFunctionsException(code: code, message: 'test'));
      expect(message, contains('Account created, but'));
    }
  });
  test(
      'signup field and nonblocking result are wired to visible UI after bootstrap',
      () {
    final source = File('lib/app/sender_mobile/sender_mobile_home.dart')
        .readAsStringSync();
    expect(source, contains('REFERRAL CODE (OPTIONAL)'));
    expect(
        source,
        contains(
            'Use a friend’s code. Rewards unlock after your first completed paid delivery.'));
    expect(source, contains('if (!_isSignIn) ...['));
    final sequence = source.substring(
        source.indexOf('Future<SenderAuthCommitResult> _authenticateSender'));
    expect(sequence.indexOf('authenticateSenderEmail('),
        lessThan(sequence.indexOf('ensureCanonicalSenderAccount')));
    expect(sequence.indexOf('ensureCanonicalSenderAccount'),
        lessThan(sequence.indexOf('applySignupReferral(')));
    expect(sequence, contains('accountCreated && bootstrap.succeeded'));
    expect(source, contains('messenger.showSnackBar'));
    expect(source, contains('if (mounted) widget.onAuthenticated()'));
    expect(source, contains('applySignupReferral('));
    expect(source, contains('showSnackBar'));
    expect(source, isNot(contains('Referral code attach failed:')));
    expect(source, isNot(contains('Web referral attach failed:')));
  });
}
