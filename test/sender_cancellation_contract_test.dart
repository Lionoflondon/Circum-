import 'dart:async';
import 'package:circum/app/delivery/cancellation_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejection, missing success and pending settlement retain tracking', () {
    for (final response in <Map<String, dynamic>>[
      {},
      {'success': false, 'status': 'settled'},
      {'success': true, 'status': 'pending_reconciliation'},
      {'success': 'true', 'status': 'settled'},
    ]) {
      expect(cancellationConfirmed(response), isFalse);
    }
    expect(
      cancellationConfirmed({'success': true, 'status': 'settled'}),
      isTrue,
    );
  });

  test(
    'preview and mutation have bounded, retryable unknown outcomes',
    () async {
      for (final stage in ['preview', 'mutation']) {
        final pending = Completer<Map<String, dynamic>>();
        await expectLater(
          boundedCancellationCall(
            pending.future,
            timeout: const Duration(milliseconds: 1),
          ),
          throwsA(isA<TimeoutException>()),
          reason: stage,
        );
        pending.complete({'success': true, 'status': 'settled'});
        final retry = await boundedCancellationCall(pending.future);
        expect(cancellationConfirmed(retry), isTrue);
      }
    },
  );
}
