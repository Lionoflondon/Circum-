import 'package:circum/app/gifts/gifts_social_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gift cannot be posted without public consent', () {
    expect(
        GiftsSocialPolicy.canPostPublicly({
          'recipientContentConsent': 'declined',
          'allowCircumSocialUse': true,
          'allowPublicPosting': true,
        }),
        isFalse);
  });

  test('brand tags require brand tagging and public consent', () {
    expect(
        GiftsSocialPolicy.canApproveBrandTags({
          'recipientContentConsent': 'granted',
          'allowCircumSocialUse': true,
          'allowPublicPosting': true,
          'allowBrandTagging': false,
        }),
        isFalse);
  });

  test('anonymous sender identity remains hidden', () {
    final safe = GiftsSocialPolicy.recipientSafeView({
      'senderId': 'private',
      'senderName': 'Private Sender',
      'senderEmail': 'private@example.com',
      'senderRevealMode': 'anonymous_until_consent',
      'senderRevealConsent': 'not_requested',
      'recipientRevealRequestStatus': 'none',
    });
    expect(safe.containsKey('senderName'), isFalse);
  });

  test('sender reveal requires mutual approval', () {
    expect(
        GiftsSocialPolicy.canRevealSender({
          'senderRevealMode': 'anonymous_until_consent',
          'senderRevealConsent': 'granted',
          'recipientRevealRequestStatus': 'approved',
        }),
        isTrue);
  });

  test('matching produces a score and human reason', () {
    final result = GiftsSocialPolicy.scoreMatch(
      {
        'userId': 'a',
        'matchConsent': true,
        'matchStatus': 'unmatched',
        'interests': ['Books', 'Travel'],
      },
      {
        'userId': 'b',
        'matchConsent': true,
        'matchStatus': 'unmatched',
        'interests': ['Books', 'Travel', 'Food'],
      },
    );
    expect(result.score, greaterThan(0));
    expect(result.reason, contains('books'));
  });
}
