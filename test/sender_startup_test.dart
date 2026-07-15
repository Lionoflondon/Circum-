import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web products render the shell and skeleton while Firebase starts', () {
    final publicEntry =
        File('lib/public_web/main_public.dart').readAsStringSync();
    final senderEntry =
        File('lib/sender_web/main_sender_web.dart').readAsStringSync();
    final riderEntry =
        File('lib/rider_web/main_rider_web.dart').readAsStringSync();
    final bootstrap =
        File('lib/shared_web/circum_web_bootstrap.dart').readAsStringSync();
    final indexSource = File('web/index.html').readAsStringSync();
    final senderSource = File('lib/web_sender_app.dart').readAsStringSync();

    for (final entry in [publicEntry, senderEntry, riderEntry]) {
      expect(entry, contains('CircumWebBootstrap('));
      expect(entry, isNot(contains('Starting Circum')));
    }
    expect(bootstrap, contains('CircumWebShell('));
    expect(bootstrap, contains('_WebPageSkeleton'));
    expect(bootstrap, contains('.timeout(widget.timeout)'));
    expect(bootstrap, contains("label: const Text('Retry')"));
    expect(senderEntry, contains('showSectionNavigation: false'));

    expect(indexSource, contains('id="startup-shell"'));
    expect(indexSource, contains('flutter-first-frame'));
    expect(indexSource, contains('startup-skeleton-hero'));
    expect(indexSource, isNot(contains('Starting Circum')));
    expect(indexSource, isNot(contains('startup-spinner')));
    expect(indexSource, contains('src="flutter_bootstrap.js"'));
    expect(indexSource, isNot(contains('_flutter.loader.loadEntrypoint')));
    expect(indexSource, isNot(contains('caches.delete')));

    final phoneStage = senderSource.substring(
      senderSource.indexOf('class _PhoneStage'),
      senderSource.indexOf('class _CircumOrderRank'),
    );
    expect(
      RegExp(r'constraints: const BoxConstraints\(maxWidth: 430\)')
          .hasMatch(phoneStage),
      isTrue,
    );
    expect(
      RegExp(
        r'width: double\.infinity,\s*height: double\.infinity,\s*constraints: const BoxConstraints\(maxWidth: 430\)',
      ).hasMatch(phoneStage),
      isTrue,
      reason: 'The responsive Sender host must give its Scaffold a height.',
    );
  });
}
