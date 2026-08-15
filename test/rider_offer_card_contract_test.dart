import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
  });

  test('Rider offer carousel remains swipeable and animated', () {
    expect(source, contains('PageView.builder'));
    expect(source, contains('PageController(viewportFraction: .92)'));
    expect(source, contains('BouncingScrollPhysics'));
  });

  test(
      'Rider offer card renders canonical route, address, ETA and IRIS fallbacks',
      () {
    expect(source, contains("job['distanceFromRider']"));
    expect(source, contains("pricing['routeFacts']"));
    expect(source, contains("routeFacts['durationSeconds']"));
    expect(source, contains("pickupDetails['address']"));
    expect(source, contains("dropoffDetails['address']"));
    expect(source, contains("irisRecommendation['recommendedVehicle']"));
    expect(source, contains("irisRecommendation['detectedItem']"));
    expect(source, contains("label: 'Rider to pickup'"));
    expect(source, contains("label: 'Delivery route'"));
    expect(source, contains("label: 'Route ETA'"));
    expect(source, contains("'Updating ETA'"));
  });
}
