import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracking map cannot swallow Sender lifecycle actions', () {
    final source = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();
    final mapStart = source.indexOf('class _SenderGoogleTrackingMapState');
    final mapEnd = source.indexOf('Set<Marker> _markers', mapStart);
    final map = source.substring(mapStart, mapEnd);

    expect(map, contains('return IgnorePointer('));
    expect(map, contains("ValueKey('sender-live-google-map')"));
    expect(source, contains('googleMapSnapshot != null && !kIsWeb'));
    expect(source, contains('googleMapSnapshot == null || kIsWeb ? 1 : .26'));
    expect(source, contains("label: canCancel"));
    expect(source, contains('onTap: canCancel ? onCancelDelivery'));
  });
}
