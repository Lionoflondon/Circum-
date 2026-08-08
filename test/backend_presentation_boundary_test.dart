import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presentation boundaries use explicit human vocabulary', () {
    final website =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    final admin =
        File('lib/app/admin/admin_phase1_shell.dart').readAsStringSync();
    final profile = File('lib/app/sender_mobile/sender_mobile_profile.dart')
        .readAsStringSync();

    expect(website, contains("'cancelled_by_sender' => 'Cancelled by sender'"));
    expect(website, contains("'circum_rider' => 'CIRCUM Rider'"));
    expect(website, contains("'iris' => 'IRIS'"));
    expect(website, contains("'vanguard' => 'Vanguard'"));
    expect(website, contains("'roth' => 'Roth'"));
    expect(website, contains("'manual_review' => 'Under review'"));
    expect(website, contains("'arrived_at_pickup' => 'Arrived at pickup'"));
    expect(website, contains("return 'Other feedback';"));
    expect(admin, contains("'manual_review' => 'Under review'"));
    expect(admin, contains("'arrived_at_pickup' => 'Arrived at pickup'"));
    expect(profile, contains("return 'Trust activity';"));
    expect(website, contains('IRIS'));
    expect(website, contains('Vanguard'));
    expect(website, contains('Roth'));

    expect(
        website,
        isNot(contains(
            "final _displayStatusLabel(String status) {\n  final normalized = status.trim().replaceAll")));
    expect(profile,
        isNot(contains("return value\n        .replaceAll('_', ' ')")));
  });

  test('canonical machine identifiers remain internal contracts', () {
    final website =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    expect(website, contains('cancelled_by_sender'));
    expect(website, contains('manual_review'));
    expect(website, contains('arrived_at_pickup'));
  });
}
