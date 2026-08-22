import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public website copy does not expose internal terminology', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    final pricing =
        File('lib/website/shared/pricing/website_delivery_pricing.dart')
            .readAsStringSync();
    final iris = File('lib/website/shared/iris/iris_weight_estimator.dart')
        .readAsStringSync();
    final giftPolicy =
        File('lib/website/shared/policies/gift_request_policy.dart')
            .readAsStringSync();
    final vanguard =
        File('lib/website/shared/policies/vanguard_protection.dart')
            .readAsStringSync();

    final publicCopy = [source, pricing, iris, giftPolicy, vanguard]
        .expand((file) => file.split('\n'))
        .where(
          (line) =>
              RegExp(
                r"(?:Text\(|title:|label:|message:|reason:|explanation:|content:|recipient:|hint:|return ')",
              ).hasMatch(line) &&
              !line.contains('_sender') &&
              !line.contains('senderRole'),
        )
        .join('\n')
        .toLowerCase();
    const forbiddenPublicPhrases = <String>[
      'sender',
      'senders',
      'circum sender',
      'sender app',
      'sender details',
      'sender identity',
      'sender email',
      'sender confirmation',
      'sender weight',
      'sender or collection contact',
      'the sender',
      'callable function',
      'cloud function',
      'closecircumaccount',
      'api endpoint',
      'database document',
      'repository metadata',
      'repository match',
    ];

    for (final phrase in forbiddenPublicPhrases) {
      expect(publicCopy, isNot(contains(phrase)), reason: phrase);
    }
    expect(publicCopy, contains('circum'));
    expect(publicCopy, contains('rider'));
  });
}
