import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender web startup is bounded and never has a blank fallback', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final indexSource = File('web/index.html').readAsStringSync();

    expect(mainSource, contains('runApp(CircumSenderStartup('));
    expect(mainSource, contains('.timeout(widget.timeout)'));
    expect(mainSource, contains('Reference: SND-START-001'));
    expect(mainSource, contains('backgroundColor: const Color(0xFF07090F)'));
    expect(mainSource, contains("label: const Text('Retry')"));

    expect(indexSource, contains('id="startup-shell"'));
    expect(indexSource, contains('flutter-first-frame'));
    expect(indexSource, contains('SND-WEB-BOOT-001'));
    expect(indexSource, contains('src="flutter_bootstrap.js"'));
    expect(indexSource, isNot(contains('_flutter.loader.loadEntrypoint')));
    expect(indexSource, isNot(contains('caches.delete')));
  });
}
