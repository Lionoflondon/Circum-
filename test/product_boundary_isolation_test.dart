import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProcessResult> runBoundary(
    String surface,
    List<String> files,
  ) {
    return Process.run('node', [
      'scripts/validate_product_boundary.js',
      '--surface=$surface',
      '--files=${files.join(',')}',
    ]);
  }

  test('Sender App accepts only Sender-owned files', () async {
    final result = await runBoundary('sender-app', [
      'lib/app/sender_mobile/sender_mobile_home.dart',
      'lib/app/send_package/bloc/send_package_bloc.dart',
      'test/sender_mobile/sender_mobile_profile_test.dart',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final payload =
        jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    expect(payload['ok'], true);
    expect(payload['surface'], 'sender-app');
  });

  test('Sender App blocks Rider contamination', () async {
    final result = await runBoundary('sender-app', [
      'lib/app/sender_mobile/sender_mobile_home.dart',
      'lib/app/rider_marketplace/rider_marketplace_view.dart',
    ]);

    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains('DEPLOYMENT BLOCKED'));
    expect(
      result.stderr.toString(),
      contains('Cross-application contamination detected.'),
    );
    expect(
      result.stderr.toString(),
      contains('lib/app/rider_marketplace/rider_marketplace_view.dart'),
    );
  });

  test('Sender App blocks backend contamination', () async {
    final result = await runBoundary('sender-app', [
      'lib/app/sender_mobile/sender_mobile_home.dart',
      'server/functions/index.js',
    ]);

    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains('DEPLOYMENT BLOCKED'));
    expect(result.stderr.toString(), contains('server/functions/index.js'));
  });

  test('Public Web blocks mobile Sender files', () async {
    final result = await runBoundary('public-web', [
      'lib/main_public_web.dart',
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ]);

    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains('DEPLOYMENT BLOCKED'));
    expect(
      result.stderr.toString(),
      contains('lib/app/sender_mobile/sender_mobile_home.dart'),
    );
  });

  test('Sender Web blocks Public Web deployment scripts', () async {
    final result = await runBoundary('sender-web', [
      'lib/main_sender_web.dart',
      'scripts/build_public_web.sh',
    ]);

    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains('DEPLOYMENT BLOCKED'));
    expect(result.stderr.toString(), contains('scripts/build_public_web.sh'));
  });
}
