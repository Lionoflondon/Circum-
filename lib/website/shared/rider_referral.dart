import 'dart:async';

const riderReferralRewardCopy =
    'Earn 5 Roth when a rider you invite is approved and completes their first paid delivery.';
const riderReferralHelper =
    'Use another rider’s code. Rewards unlock after approval and your first completed delivery.';

String normalizeRiderReferral(String value) {
  final normalized = value.trim().toUpperCase().replaceAll(
        RegExp('[^A-Z0-9]'),
        '',
      );
  return normalized.substring(0, normalized.length.clamp(0, 24));
}

String riderReferralMessage(String status) => switch (status) {
      'empty' => 'Rider account created.',
      'applied' ||
      'SIGNED_UP' =>
        'Rider account created. Referral code applied. Rewards unlock after approval and your first completed delivery.',
      'not_found' ||
      'invalid' =>
        'Rider account created, but that referral code was not found.',
      'rejected_self_referral' ||
      'rejected' =>
        'Rider account created, but your own referral code cannot be used.',
      'already_attached' => 'Rider account created. Referral already linked.',
      'timeout' =>
        'Rider account created, but referral verification timed out. Try again from Rider Referrals.',
      _ => 'Rider account created, but referral code could not be applied.',
    };

Future<String> applyRiderReferral({
  required String code,
  required Future<String> Function(String code) attach,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (code.trim().isEmpty) return riderReferralMessage('empty');
  final normalized = normalizeRiderReferral(code);
  if (normalized.isEmpty) return riderReferralMessage('invalid');
  try {
    return riderReferralMessage(await attach(normalized).timeout(timeout));
  } on TimeoutException {
    return riderReferralMessage('timeout');
  } catch (_) {
    return riderReferralMessage('unknown_error');
  }
}
