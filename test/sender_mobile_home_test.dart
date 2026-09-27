import 'dart:io';

import 'package:circum/app/sender_mobile/sender_mobile_home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender dashboard service copy is production ready', () {
    expect(
      senderMobileDashboardServiceSubtitles['Gifts'],
      'Thoughtful gifts, delivered.',
    );
  });

  test('service cards do not inherit an aggregate summary failure', () {
    final source = File('lib/app/sender_mobile/sender_mobile_home.dart')
        .readAsStringSync();
    final canonicalHome = source.substring(
      source.indexOf('class _CanonicalSenderHome'),
      source.indexOf('class _SenderDashboard'),
    );

    expect(canonicalHome, contains("status: '',"));
    expect(
      canonicalHome,
      isNot(contains("status: _summaryError != null ? 'Unavailable'")),
    );
    expect(source,
        isNot(contains("if (hasError) return 'Unavailable right now';")));
  });
}
