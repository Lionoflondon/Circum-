import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web Rider offer card consumes the safe projection contract', () {
    final source = File(
      'lib/website/shared/circum_website_app.dart',
    ).readAsStringSync();

    expect(source, contains("job['pickupLocality']"));
    expect(source, contains("job['dropoffLocality']"));
    expect(source, contains("job['distanceText']"));
    expect(source, contains("job['durationText']"));
    expect(source, contains("job['riderEarning']"));
    expect(source, contains("job['minimumVehicle']"));
    expect(source, contains("job['packageDescription']"));
    expect(source, contains("job['weightKg']"));
    expect(source, contains("job['offerExpiresAt']"));
    expect(source, contains('Rider payout'));
  });
}
