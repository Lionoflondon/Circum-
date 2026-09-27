import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender browser smoke uses a valid locale and waits for real startup', () {
    final source = File('test/sender_mobile/sender_browser_smoke.mjs')
        .readAsStringSync();

    expect(source, contains("locale: 'en-GB'"));
    expect(source, contains('return !htmlFallback && (recovery || (canvas'));
    expect(source, contains('timeout: 60000'));
    expect(source, contains("if (htmlFallback) throw new Error"));
  });
}
