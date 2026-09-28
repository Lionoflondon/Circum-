import 'dart:convert';

import 'package:circum/app/sender_mobile/sender_booking_quote_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('quote transport sends Auth and App Check with callable envelope',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'result': {'quoteId': 'quote_qa', 'total': 12.5}
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await invokeSenderBookingQuote(
      {'selectedSpeed': 'standard'},
      idToken: 'id-token',
      appCheckToken: 'app-check-token',
      client: client,
    );

    expect(result['quoteId'], 'quote_qa');
    expect(captured.url.host, contains('circum-sender-booking-quotes'));
    expect(captured.url.path, '/createSenderBookingQuote');
    expect(captured.headers['authorization'], 'Bearer id-token');
    expect(captured.headers['x-firebase-appcheck'], 'app-check-token');
    expect(jsonDecode(captured.body), {
      'data': {'selectedSpeed': 'standard'},
    });
  });

  test('quote transport preserves safe service errors', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': {
              'status': 'UNAUTHENTICATED',
              'message': 'Sign in to continue.',
            },
          }),
          401,
        ));

    await expectLater(
      invokeSenderBookingQuote(
        const {},
        idToken: 'id-token',
        appCheckToken: 'app-check-token',
        client: client,
      ),
      throwsA(isA<SenderBookingQuoteApiException>().having(
        (error) => error.status,
        'status',
        'UNAUTHENTICATED',
      )),
    );
  });

  test('quote service URL contains no provider credential', () {
    expect(senderBookingQuoteServiceUrl, isNot(contains('AIza')));
    expect(senderBookingQuoteServiceUrl, isNot(contains('STRIPE')));
  });
}
