import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';

String normalizeSignupReferral(String value) {
  final code = value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return code.substring(0, code.length.clamp(0, 24));
}

String referralSignupMessage(String status) => switch (status) {
      'empty' => 'Account created.',
      'applied' ||
      'SIGNED_UP' =>
        'Account created. Referral code applied. Rewards unlock after your first completed paid delivery.',
      'not_found' ||
      'invalid' =>
        'Account created, but that referral code was not found. You can continue using Circum.',
      'rejected_self_referral' ||
      'rejected' =>
        'Account created, but your own referral code cannot be used.',
      'timeout' =>
        'Account created, but referral verification timed out. Try again from Wallet > Referrals.',
      'already_attached' => 'Account created. Referral already linked.',
      _ =>
        'Account created, but referral code could not be applied. You can continue using Circum.',
    };

Future<String> applySignupReferral(
    String input, Future<dynamic> Function(String) attach,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final code = normalizeSignupReferral(input);
  if (input.trim().isEmpty) return referralSignupMessage('empty');
  if (code.isEmpty) return referralSignupMessage('invalid');
  try {
    final result = await attach(code).timeout(timeout);
    return referralSignupMessage(
        result is Map ? '${result['status']}' : 'unknown');
  } on TimeoutException {
    return referralSignupMessage('timeout');
  } on FirebaseFunctionsException catch (error) {
    return referralSignupMessage(switch (error.code) {
      'not-found' => 'not_found',
      'invalid-argument' => 'invalid',
      'deadline-exceeded' || 'unavailable' => 'timeout',
      _ => 'unknown',
    });
  } catch (_) {
    return referralSignupMessage('unknown');
  }
}
