import 'dart:async';

import 'package:circum/app/send_package/models/sender_delivery_restoration.dart';
import 'package:flutter_test/flutter_test.dart';

SenderRestorationRecord _record(String status) => SenderRestorationRecord(
      documentId: 'delivery-1',
      data: {
        'requestId': 'delivery-1',
        'senderId': 'sender-1',
        'status': status,
      },
    );

void main() {
  group('canonical Sender delivery restoration', () {
    for (final status in const [
      'cancelled',
      'cancelled_by_sender',
      'delivered',
      'completed',
    ]) {
      test('$status is cleared before a watcher can attach', () async {
        final coordinator = SenderDeliveryRestorationCoordinator();
        final cleared = <String>[];
        final restored = <SenderRestorationRecord>[];
        final freshReasons = <String>[];
        var watchCalls = 0;

        final outcome = await coordinator.restore(
          requestId: 'delivery-1',
          senderId: 'sender-1',
          load: (_, __) async => _record(status),
          watch: (_) {
            watchCalls += 1;
            return const Stream.empty();
          },
          clearPointer: (requestId) async => cleared.add(requestId),
          onRestore: (record, _) => restored.add(record),
          onTerminal: (_, __) =>
              fail('An initially terminal delivery cannot be emitted.'),
          onFresh: (_, reason, __) => freshReasons.add(reason),
          onError: (_, __) {},
        );

        expect(outcome, SenderRestorationOutcome.fresh);
        expect(cleared, ['delivery-1']);
        expect(restored, isEmpty);
        expect(watchCalls, 0);
        expect(freshReasons, ['terminal_delivery']);
        await coordinator.close();
      });
    }

    test('missing delivery clears its stale pointer and starts fresh',
        () async {
      final coordinator = SenderDeliveryRestorationCoordinator();
      final cleared = <String>[];
      final freshReasons = <String>[];

      final outcome = await coordinator.restore(
        requestId: 'missing-delivery',
        senderId: 'sender-1',
        load: (_, __) async => null,
        watch: (_) => const Stream.empty(),
        clearPointer: (requestId) async => cleared.add(requestId),
        onRestore: (_, __) => fail('A missing delivery cannot restore.'),
        onTerminal: (_, __) => fail('A missing delivery cannot be terminal.'),
        onFresh: (_, reason, __) => freshReasons.add(reason),
        onError: (_, __) {},
      );

      expect(outcome, SenderRestorationOutcome.fresh);
      expect(cleared, ['missing-delivery']);
      expect(freshReasons, ['missing_delivery']);
      await coordinator.close();
    });

    test('a genuine active delivery restores and remains watched', () async {
      final coordinator = SenderDeliveryRestorationCoordinator();
      final snapshots = StreamController<SenderRestorationRecord?>();
      final restoredStatuses = <String>[];
      var watchCalls = 0;

      final outcome = await coordinator.restore(
        requestId: 'delivery-1',
        senderId: 'sender-1',
        load: (_, __) async => _record('accepted'),
        watch: (_) {
          watchCalls += 1;
          return snapshots.stream;
        },
        clearPointer: (_) async {},
        onRestore: (record, _) =>
            restoredStatuses.add('${record.data['status']}'),
        onTerminal: (_, __) => fail('This delivery remains active.'),
        onFresh: (_, __, ___) => fail('An active delivery must not clear.'),
        onError: (_, __) {},
      );
      snapshots.add(_record('navigating_to_pickup'));
      await Future<void>.delayed(Duration.zero);

      expect(outcome, SenderRestorationOutcome.restored);
      expect(watchCalls, 1);
      expect(restoredStatuses, ['accepted', 'navigating_to_pickup']);
      await coordinator.close();
      await snapshots.close();
    });

    test('terminal watcher update invalidates delayed and queued emissions',
        () async {
      final coordinator = SenderDeliveryRestorationCoordinator();
      final snapshots = StreamController<SenderRestorationRecord?>();
      final clearStarted = Completer<void>();
      final allowClear = Completer<void>();
      final restoredStatuses = <String>[];
      final terminalStatuses = <String>[];

      await coordinator.restore(
        requestId: 'delivery-1',
        senderId: 'sender-1',
        load: (_, __) async => _record('arrived_at_pickup'),
        watch: (_) => snapshots.stream,
        clearPointer: (_) async {
          clearStarted.complete();
          await allowClear.future;
        },
        onRestore: (record, _) =>
            restoredStatuses.add('${record.data['status']}'),
        onTerminal: (record, _) =>
            terminalStatuses.add('${record.data['status']}'),
        onFresh: (_, __, ___) {},
        onError: (_, __) {},
      );

      snapshots.add(_record('cancelled'));
      await clearStarted.future;
      snapshots.add(_record('accepted'));
      allowClear.complete();
      await Future<void>.delayed(Duration.zero);

      expect(restoredStatuses, ['arrived_at_pickup']);
      expect(terminalStatuses, ['cancelled']);
      await coordinator.close();
      await snapshots.close();
    });

    test('reset invalidates an already queued active snapshot', () async {
      final coordinator = SenderDeliveryRestorationCoordinator();
      final snapshots = StreamController<SenderRestorationRecord?>();
      final restoredStatuses = <String>[];

      await coordinator.restore(
        requestId: 'delivery-1',
        senderId: 'sender-1',
        load: (_, __) async => _record('requested'),
        watch: (_) => snapshots.stream,
        clearPointer: (_) async {},
        onRestore: (record, _) =>
            restoredStatuses.add('${record.data['status']}'),
        onTerminal: (_, __) => fail('Reset must suppress terminal updates.'),
        onFresh: (_, __, ___) {},
        onError: (_, __) {},
      );
      final previousGeneration = coordinator.generation;
      await coordinator.reset();
      snapshots.add(_record('cancelled'));
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.isCurrent(previousGeneration), isFalse);
      expect(restoredStatuses, ['requested']);
      await coordinator.close();
      await snapshots.close();
    });

    test('repeated entry after terminal cleanup remains fresh', () async {
      final coordinator = SenderDeliveryRestorationCoordinator();
      SenderRestorationRecord? persisted = _record('cancelled');
      final cleared = <String>[];
      final freshReasons = <String>[];
      var watchCalls = 0;

      Future<SenderRestorationOutcome> enterBooking() {
        return coordinator.restore(
          requestId: 'delivery-1',
          senderId: 'sender-1',
          load: (_, __) async => persisted,
          watch: (_) {
            watchCalls += 1;
            return const Stream.empty();
          },
          clearPointer: (requestId) async {
            cleared.add(requestId);
            persisted = null;
          },
          onRestore: (_, __) => fail('Terminal history cannot restore.'),
          onTerminal: (_, __) => fail('Initial terminal history cannot emit.'),
          onFresh: (_, reason, __) => freshReasons.add(reason),
          onError: (_, __) {},
        );
      }

      expect(await enterBooking(), SenderRestorationOutcome.fresh);
      expect(await enterBooking(), SenderRestorationOutcome.fresh);
      expect(freshReasons, ['terminal_delivery', 'missing_delivery']);
      expect(cleared, ['delivery-1', 'delivery-1']);
      expect(watchCalls, 0);
      await coordinator.close();
    });

    test('terminal classification is fail-closed across status aliases', () {
      expect(
        SenderDeliveryRestorationPolicy.classify({
          'status': 'accepted',
          'deliveryStatus': 'cancelled_by_rider',
        }),
        SenderDeliveryRestorationDisposition.terminal,
      );
      expect(
        SenderDeliveryRestorationPolicy.classify({
          'status': 'requested',
          'archived': true,
        }),
        SenderDeliveryRestorationDisposition.terminal,
      );
      expect(
        SenderDeliveryRestorationPolicy.classify({'status': 'future_state'}),
        SenderDeliveryRestorationDisposition.unresolved,
      );
    });
  });
}
