import 'dart:async';

enum SenderDeliveryRestorationDisposition {
  restorable,
  terminal,
  unresolved,
}

class SenderDeliveryRestorationPolicy {
  const SenderDeliveryRestorationPolicy._();

  static const terminalStatuses = <String>{
    'complete',
    'completed',
    'delivered',
    'delivery_completed',
    'cancelled',
    'canceled',
    'cancelled_by_sender',
    'cancelled_by_rider',
    'cancelled_admin',
    'cancelled_verified_discrepancy',
    'sender_no_show_pickup',
    'admin_removed_stale',
    'archived',
    'archived_stale',
    'archived_expired',
    'expired',
    'voided',
    'failed',
    'failed_delivery',
    'rejected',
  };

  static const restorableStatuses = <String>{
    'requested',
    'pending',
    'unmatched',
    'searching',
    'finding_rider',
    'awaiting_rider',
    'broadcast',
    'broadcasted',
    'accepted',
    'assigned',
    'rider_assigned',
    'navigating_to_pickup',
    'en_route_to_pickup',
    'arrived_at_pickup',
    'rider_arrived_pickup',
    'waiting',
    'pickup_verification',
    'pickup_verified',
    'collected',
    'picked_up',
    'out_for_delivery',
    'outfordelivery',
    'in_transit',
    'navigating_to_dropoff',
    'arrived_at_dropoff',
    'pin_required',
    'handover_pending',
    'issue',
    'issue_reported',
  };

  static String normalize(Object? value) =>
      '${value ?? ''}'.trim().toLowerCase().replaceAll(RegExp(r'[-\s]+'), '_');

  static SenderDeliveryRestorationDisposition classify(
    Map<String, dynamic> delivery,
  ) {
    final statuses = <String>{
      normalize(delivery['status']),
      normalize(delivery['deliveryStatus']),
      normalize(delivery['deliveryStage']),
      normalize(delivery['flowStatus']),
    }..remove('');

    if (delivery['active'] == false ||
        delivery['archived'] == true ||
        statuses.any(terminalStatuses.contains)) {
      return SenderDeliveryRestorationDisposition.terminal;
    }
    if (statuses.any(restorableStatuses.contains)) {
      return SenderDeliveryRestorationDisposition.restorable;
    }
    return SenderDeliveryRestorationDisposition.unresolved;
  }

  static bool isTerminalStatus(Object? status) =>
      terminalStatuses.contains(normalize(status));
}

class SenderRestorationRecord {
  final String documentId;
  final Map<String, dynamic> data;

  const SenderRestorationRecord({
    required this.documentId,
    required this.data,
  });

  String get requestId =>
      '${data['requestId'] ?? data['deliveryId'] ?? documentId}'.trim();
}

enum SenderRestorationOutcome {
  restored,
  fresh,
  unresolved,
  superseded,
}

typedef SenderRestorationLoader = Future<SenderRestorationRecord?> Function(
  String requestId,
  String senderId,
);
typedef SenderRestorationWatcher = Stream<SenderRestorationRecord?> Function(
  String documentId,
);
typedef SenderRestorationRecordCallback = FutureOr<void> Function(
  SenderRestorationRecord record,
  int generation,
);
typedef SenderRestorationFreshCallback = FutureOr<void> Function(
  String requestId,
  String reason,
  int generation,
);

class SenderDeliveryRestorationCoordinator {
  StreamSubscription<SenderRestorationRecord?>? _subscription;
  int _generation = 0;

  int get generation => _generation;

  bool isCurrent(int generation) => generation == _generation;

  Future<SenderRestorationOutcome> restore({
    required String requestId,
    required String senderId,
    required SenderRestorationLoader load,
    required SenderRestorationWatcher watch,
    required Future<void> Function(String requestId) clearPointer,
    required SenderRestorationRecordCallback onRestore,
    required SenderRestorationRecordCallback onTerminal,
    required SenderRestorationFreshCallback onFresh,
    required FutureOr<void> Function(String message, int generation) onError,
  }) async {
    final normalized = requestId.trim();
    final generation = await _beginCycle();
    if (normalized.isEmpty) {
      return SenderRestorationOutcome.fresh;
    }

    final record = await load(normalized, senderId);
    if (!isCurrent(generation)) {
      return SenderRestorationOutcome.superseded;
    }
    if (record == null) {
      await clearPointer(normalized);
      if (!isCurrent(generation)) {
        return SenderRestorationOutcome.superseded;
      }
      await onFresh(normalized, 'missing_delivery', generation);
      return SenderRestorationOutcome.fresh;
    }

    final initialOutcome = await _classify(
      record: record,
      requestId: normalized,
      generation: generation,
      clearPointer: clearPointer,
      onRestore: onRestore,
      onTerminal: onTerminal,
      onFresh: onFresh,
      onError: onError,
      initial: true,
    );
    if (initialOutcome != SenderRestorationOutcome.restored ||
        !isCurrent(generation)) {
      return initialOutcome;
    }

    _subscription = watch(record.documentId).listen(
      (snapshot) {
        if (!isCurrent(generation)) return;
        if (snapshot == null) {
          unawaited(_handleMissingSnapshot(
            requestId: normalized,
            generation: generation,
            clearPointer: clearPointer,
            onFresh: onFresh,
          ));
          return;
        }
        unawaited(_classify(
          record: snapshot,
          requestId: normalized,
          generation: generation,
          clearPointer: clearPointer,
          onRestore: onRestore,
          onTerminal: onTerminal,
          onFresh: onFresh,
          onError: onError,
          initial: false,
        ));
      },
      onError: (Object _) {
        if (isCurrent(generation)) {
          onError('Unable to load live delivery status.', generation);
        }
      },
    );
    return SenderRestorationOutcome.restored;
  }

  Future<int> reset() async {
    final generation = ++_generation;
    await _subscription?.cancel();
    _subscription = null;
    return generation;
  }

  Future<int> _beginCycle() => reset();

  Future<SenderRestorationOutcome> _classify({
    required SenderRestorationRecord record,
    required String requestId,
    required int generation,
    required Future<void> Function(String requestId) clearPointer,
    required SenderRestorationRecordCallback onRestore,
    required SenderRestorationRecordCallback onTerminal,
    required SenderRestorationFreshCallback onFresh,
    required FutureOr<void> Function(String message, int generation) onError,
    required bool initial,
  }) async {
    if (!isCurrent(generation)) {
      return SenderRestorationOutcome.superseded;
    }
    final disposition = SenderDeliveryRestorationPolicy.classify(record.data);
    if (disposition == SenderDeliveryRestorationDisposition.terminal) {
      await reset();
      await clearPointer(requestId);
      final currentGeneration = _generation;
      if (initial) {
        await onFresh(requestId, 'terminal_delivery', currentGeneration);
      } else {
        await onTerminal(record, currentGeneration);
      }
      return SenderRestorationOutcome.fresh;
    }
    if (disposition == SenderDeliveryRestorationDisposition.unresolved) {
      await onError(
        'That delivery has an unsupported restoration status.',
        generation,
      );
      return SenderRestorationOutcome.unresolved;
    }
    await onRestore(record, generation);
    return SenderRestorationOutcome.restored;
  }

  Future<void> _handleMissingSnapshot({
    required String requestId,
    required int generation,
    required Future<void> Function(String requestId) clearPointer,
    required SenderRestorationFreshCallback onFresh,
  }) async {
    if (!isCurrent(generation)) return;
    await reset();
    await clearPointer(requestId);
    await onFresh(requestId, 'missing_delivery', _generation);
  }

  Future<void> close() => reset();
}
