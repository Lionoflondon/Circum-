import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../lib/website/shared/policies/signup_referral.dart';
import '../lib/web_platform_routing.dart';

void main() {
  test('join link resolves to signup with normalized prefill', () {
    final route = resolveCircumWebRoute(
        Uri.parse('https://circumuk.com/join/a%20b-12'),
        adminHostingTarget: false,
        publicHostingHost: true);
    expect(route.referralCode, 'AB12');
    expect(route.surface, CircumWebSurface.sender);
    expect(route.canonicalPath, '/send');
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
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    expect(source, contains('REFERRAL CODE (OPTIONAL)'));
    expect(
        source,
        contains(
            'Use a friend’s code. Rewards unlock after your first completed paid delivery.'));
    final sequence = source.substring(
        source.indexOf('Future<void> _signUpSender()'),
        source.indexOf('Future<void> _sendSenderPasswordReset()'));
    expect(sequence.indexOf('createUserWithEmailAndPassword'),
        lessThan(sequence.indexOf('_allowSenderUser(user)')));
    expect(sequence.indexOf('updateSenderProfile'),
        lessThan(sequence.indexOf('applySignupReferral(')));
    expect(source, contains('if (signupMode) ...['));
    expect(
        source,
        contains(
            '_senderReferralCode.text = normalizeSignupReferral(widget.referralCode!)'));
    expect(source, contains('applySignupReferral('));
    expect(source, contains('showSnackBar'));
    expect(source, isNot(contains('Referral code attach failed:')));
    expect(source, isNot(contains('Web referral attach failed:')));
  });
}
