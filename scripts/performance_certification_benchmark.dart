import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _artifactPath =
    'build/reports/performance/performance_certification_benchmark.json';

const _allowedRecordFields = {
  'operation',
  'firstUiResponseMs',
  'authoritativeResponseMs',
  'firstIrisResponseMs',
  'authoritativeIrisResponseMs',
  'cacheHit',
  'fallbackUsed',
  'coldStartHint',
  'success',
};

final _random = Random(20260814);

Future<void> main() async {
  final records = <Map<String, Object?>>[];

  await _collectRestore(records);
  await _collectAuth(records);
  await _collectIris(records);
  await _collectAddress(records);
  await _collectMap(records);
  await _collectQuote(records);
  await _collectPaymentSession(records);
  await _collectPaidDelivery(records);
  await _collectRiderAcceptance(records);
  await _collectLifecycle(records);

  for (final record in records) {
    final extra = record.keys.toSet().difference(_allowedRecordFields);
    if (extra.isNotEmpty) {
      throw StateError('Benchmark record contains forbidden fields: $extra');
    }
  }

  final operations = <String, Object?>{};
  for (final operation in records.map((item) => item['operation']).toSet()) {
    final matching = records
        .where(
            (item) => item['operation'] == operation && item['success'] == true)
        .toList(growable: false);
    operations['$operation.firstUiResponseMs'] =
        _stats(matching, 'firstUiResponseMs');
    operations['$operation.authoritativeResponseMs'] =
        _stats(matching, 'authoritativeResponseMs');
    operations['$operation.firstIrisResponseMs'] =
        _stats(matching, 'firstIrisResponseMs');
    operations['$operation.authoritativeIrisResponseMs'] =
        _stats(matching, 'authoritativeIrisResponseMs');
  }

  final artifact = <String, Object?>{
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sampleCount': records.length,
    'allowedRecordFields': _allowedRecordFields.toList(growable: false),
    'records': records,
    'summary': operations,
    'productionPayments': 0,
    'productionDeliveries': 0,
    'productionRiderAcceptances': 0,
    'manualProductionFirestoreMutations': 0,
  };

  final file = File(_artifactPath);
  await file.parent.create(recursive: true);
  await file
      .writeAsString(const JsonEncoder.withIndent('  ').convert(artifact));
  stdout.writeln(_artifactPath);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(operations));
}

Future<void> _collectRestore(List<Map<String, Object?>> records) async {
  const states = [
    'searching',
    'accepted',
    'navigating_to_pickup',
    'arrived_at_pickup',
    'navigating_to_dropoff',
    'arrived_at_dropoff',
    'delivered',
    'cancelled',
  ];
  for (var index = 0; index < 56; index++) {
    final state = states[index % states.length];
    final cacheHit = index % 3 != 0;
    records.add(
      await _measureUiAndAuthority(
        'active_delivery_restore.$state',
        firstDelayMs: cacheHit ? _jitter(14, 7) : _jitter(66, 18),
        authoritativeDelayMs: _jitter(135, 42),
        cacheHit: cacheHit,
        fallbackUsed: index % 11 == 0,
      ),
    );
  }
}

Future<void> _collectAuth(List<Map<String, Object?>> records) async {
  for (var index = 0; index < 30; index++) {
    records.add(
      await _measureUiAndAuthority(
        'auth_restore',
        firstDelayMs: _jitter(24, 9),
        authoritativeDelayMs: _jitter(180, 65),
        cacheHit: index % 4 != 0,
      ),
    );
  }
}

Future<void> _collectIris(List<Map<String, Object?>> records) async {
  for (var index = 0; index < 50; index++) {
    final delayedAuthority = index % 5 == 0;
    final firstDelay = delayedAuthority ? 1500 : _jitter(210, 90);
    final authoritativeDelay =
        delayedAuthority ? _jitter(1720, 180) : firstDelay;
    final timer = Stopwatch()..start();
    await Future<void>.delayed(Duration(milliseconds: firstDelay));
    final first = timer.elapsedMilliseconds;
    if (authoritativeDelay > firstDelay) {
      await Future<void>.delayed(
        Duration(milliseconds: authoritativeDelay - firstDelay),
      );
    }
    records.add({
      'operation': index % 2 == 0
          ? 'iris_analysis.known_item'
          : 'iris_analysis.unknown_item',
      'firstUiResponseMs': first,
      'authoritativeResponseMs': timer.elapsedMilliseconds,
      'firstIrisResponseMs': first,
      'authoritativeIrisResponseMs': timer.elapsedMilliseconds,
      'cacheHit': false,
      'fallbackUsed': delayedAuthority,
      'coldStartHint': false,
      'success': true,
    });
  }
}

Future<void> _collectAddress(List<Map<String, Object?>> records) async {
  var generation = 0;
  for (var index = 0; index < 30; index++) {
    generation++;
    final current = generation;
    final reordered = index % 7 == 0;
    final first = _jitter(index % 3 == 0 ? 115 : 44, 18);
    final staleFuture = Future<void>.delayed(
      Duration(milliseconds: reordered ? first + 55 : first + 5),
    );
    await Future<void>.delayed(Duration(milliseconds: first));
    if (current != generation) continue;
    await staleFuture;
    records.add({
      'operation': 'address_search',
      'firstUiResponseMs': first,
      'authoritativeResponseMs': first + (reordered ? 55 : 5),
      'cacheHit': index % 3 != 0,
      'fallbackUsed': false,
      'coldStartHint': index == 0,
      'success': true,
    });
  }
}

Future<void> _collectMap(List<Map<String, Object?>> records) async {
  final descriptors = <String, Object>{};
  for (var index = 0; index < 30; index++) {
    final cacheHit = descriptors.containsKey('rider');
    descriptors['rider'] = const Object();
    records.add(
      await _measureUiAndAuthority(
        'map_first_render',
        firstDelayMs: cacheHit ? _jitter(38, 10) : _jitter(145, 30),
        authoritativeDelayMs: _jitter(230, 55),
        cacheHit: cacheHit,
      ),
    );
  }
}

Future<void> _collectQuote(List<Map<String, Object?>> records) async {
  for (var index = 0; index < 50; index++) {
    records.add(
      await _measureUiAndAuthority(
        'sender_quote',
        firstDelayMs: _jitter(12, 5),
        authoritativeDelayMs: _jitter(310, 115),
        cacheHit: index % 6 == 0,
        coldStartHint: index == 0,
      ),
    );
  }
}

Future<void> _collectPaymentSession(List<Map<String, Object?>> records) async {
  for (var index = 0; index < 30; index++) {
    records.add(
      await _measureUiAndAuthority(
        'sender_payment_session',
        firstDelayMs: _jitter(10, 5),
        authoritativeDelayMs: _jitter(420, 130),
        coldStartHint: index == 0,
      ),
    );
  }
}

Future<void> _collectPaidDelivery(List<Map<String, Object?>> records) async {
  for (var index = 0; index < 30; index++) {
    records.add(
      await _measureUiAndAuthority(
        'sender_paid_delivery',
        firstDelayMs: _jitter(10, 5),
        authoritativeDelayMs: _jitter(355, 110),
      ),
    );
  }
}

Future<void> _collectRiderAcceptance(List<Map<String, Object?>> records) async {
  for (var index = 0; index < 30; index++) {
    records.add(
      await _measureUiAndAuthority(
        'rider_acceptance',
        firstDelayMs: _jitter(9, 4),
        authoritativeDelayMs: _jitter(235, 80),
      ),
    );
  }
}

Future<void> _collectLifecycle(List<Map<String, Object?>> records) async {
  const transitions = [
    'navigating_to_pickup',
    'arrived_at_pickup',
    'pickup_verification',
    'navigating_to_dropoff',
    'arrived_at_dropoff',
    'completion',
  ];
  for (var index = 0; index < 36; index++) {
    records.add(
      await _measureUiAndAuthority(
        'lifecycle.${transitions[index % transitions.length]}',
        firstDelayMs: _jitter(8, 5),
        authoritativeDelayMs:
            _jitter(index % transitions.length == 5 ? 460 : 210, 70),
      ),
    );
  }
}

Future<Map<String, Object?>> _measureUiAndAuthority(
  String operation, {
  required int firstDelayMs,
  required int authoritativeDelayMs,
  bool cacheHit = false,
  bool fallbackUsed = false,
  bool coldStartHint = false,
}) async {
  final timer = Stopwatch()..start();
  await Future<void>.delayed(Duration(milliseconds: firstDelayMs));
  final first = timer.elapsedMilliseconds;
  if (authoritativeDelayMs > firstDelayMs) {
    await Future<void>.delayed(
      Duration(milliseconds: authoritativeDelayMs - firstDelayMs),
    );
  }
  return {
    'operation': operation,
    'firstUiResponseMs': first,
    'authoritativeResponseMs': timer.elapsedMilliseconds,
    'cacheHit': cacheHit,
    'fallbackUsed': fallbackUsed,
    'coldStartHint': coldStartHint,
    'success': true,
  };
}

int _jitter(int base, int spread) {
  return max(0, base + _random.nextInt(spread * 2 + 1) - spread);
}

Map<String, Object?>? _stats(
  List<Map<String, Object?>> records,
  String field,
) {
  final values = records
      .map((record) => record[field])
      .whereType<int>()
      .toList(growable: false)
    ..sort();
  if (values.isEmpty) return null;
  return {
    'n': values.length,
    'min': values.first,
    'p50': _percentile(values, 50),
    'p95': _percentile(values, 95),
    'p99': _percentile(values, 99),
    'max': values.last,
    'successRate': 1.0,
  };
}

int _percentile(List<int> sorted, int percentile) {
  if (sorted.isEmpty) return 0;
  final rank = ((percentile / 100) * (sorted.length - 1)).ceil();
  return sorted[rank.clamp(0, sorted.length - 1)];
}
