import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gifts Health and Business do not expose unavailable fallbacks', () {
    const paths = <String>[
      'lib/app/sender_mobile/gift_campaign_view.dart',
      'lib/app/sender_mobile/gift_payment_view.dart',
      'lib/app/sender_mobile/gift_story_view.dart',
      'lib/app/health_plus/view/health_plus.dart',
      'lib/app/business/business_access_view.dart',
      'lib/app/business/business_repository.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync().toLowerCase();
      expect(source, isNot(contains('unavailable')), reason: path);
    }

    final giftPayment = File(paths[1]).readAsStringSync();
    expect(giftPayment, contains('Refresh Roth balance'));
    expect(giftPayment, isNot(contains('continue securely by card')));

    final giftCampaign = File(paths[0]).readAsStringSync();
    expect(
        giftCampaign, contains('Refresh your Roth balance before continuing.'));
    expect(giftCampaign, isNot(contains('Choose card to continue securely')));
  });
}
