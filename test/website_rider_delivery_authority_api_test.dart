import 'dart:convert';
import 'dart:io';

import 'package:circum/website/shared/rider_delivery_authority_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('website Rider authority preserves Auth and App Check envelope',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
          jsonEncode({
            'result': {'nearestRequests': []}
          }),
          200);
    });

    final result = await invokeRiderDeliveryAuthority(
      'getAvailableRequests',
      const {},
      idToken: 'id-token',
      appCheckToken: 'app-check-token',
      client: client,
    );

    expect(captured.url.host, contains('circum-rider-delivery-authority'));
    expect(captured.url.path, '/getAvailableRequests');
    expect(captured.headers['authorization'], 'Bearer id-token');
    expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
    expect(jsonDecode(captured.body), {'data': {}});
    expect(result, {'nearestRequests': []});
  });

  test('migrated tracking routes retain the same protected envelope', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode({'result': {'status': 'accepted'}}), 200);
    });
    for (final operation in [
      'updateDeliveryTrackingStatus',
      'updateDeliveryLiveLocation',
    ]) {
      final result = await invokeRiderDeliveryAuthority(
        operation,
        {'deliveryId': 'qa-delivery'},
        idToken: 'id-token',
        appCheckToken: 'app-check-token',
        client: client,
      );
      expect(result['status'], 'accepted');
    }
    expect(requests.map((request) => request.url.path), [
      '/updateDeliveryTrackingStatus',
      '/updateDeliveryLiveLocation',
    ]);
    for (final request in requests) {
      expect(request.headers['authorization'], 'Bearer id-token');
      expect(request.headers['x-firebase-appcheck'], 'app-check-token');
      expect(jsonDecode(request.body), {'data': {'deliveryId': 'qa-delivery'}});
    }
  });

  test('all website Rider callers use migrated routes', () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    expect(source, isNot(contains("httpsCallable('getAvailableRequests')")));
    expect(
        source,
        contains(
            "callRiderDeliveryAuthority(\n          'getAvailableRequests'"));
    expect(source, contains("action == 'verify_receiver_pin'"));
    expect(source, contains("callRiderDeliveryAuthority('completeDelivery'"));
    expect(source,
        contains("callRiderDeliveryAuthority('updateDeliveryTrackingStatus'"));
    expect(source,
        contains("callRiderDeliveryAuthority('updateDeliveryLiveLocation'"));
    expect(source,
        isNot(contains("httpsCallable('updateDeliveryTrackingStatus')")));
    expect(source, isNot(contains("httpsCallable('updateDeliveryLiveLocation')")));
  });
}
