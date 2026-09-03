import 'dart:async';

import 'package:circum/app/send_package/repo/route_request_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const origin = RouteCoordinate(51.50001, -0.10001);
  const destination = RouteCoordinate(51.60001, -0.20001);

  test('fresh identical route requests use one provider call', () async {
    var calls = 0;
    final coordinator = RouteRequestCoordinator<int>(
      load: (_, __) async => ++calls,
    );
    expect(await coordinator.resolve(origin, destination), 1);
    expect(await coordinator.resolve(origin, destination), 1);
    expect(calls, 1);
  });

  test('identical in-flight route requests share one future', () async {
    var calls = 0;
    final response = Completer<int>();
    final coordinator = RouteRequestCoordinator<int>(
      load: (_, __) {
        calls++;
        return response.future;
      },
    );
    final first = coordinator.resolve(origin, destination);
    final second = coordinator.resolve(origin, destination);
    response.complete(7);
    expect(await Future.wait([first, second]), [7, 7]);
    expect(calls, 1);
  });

  test('expired route cache performs a new provider call', () async {
    var now = DateTime.utc(2026, 1, 1);
    var calls = 0;
    final coordinator = RouteRequestCoordinator<int>(
      ttl: const Duration(minutes: 2),
      clock: () => now,
      load: (_, __) async => ++calls,
    );
    expect(await coordinator.resolve(origin, destination), 1);
    now = now.add(const Duration(minutes: 3));
    expect(await coordinator.resolve(origin, destination), 2);
  });

  test('failed requests are not cached', () async {
    var calls = 0;
    final coordinator = RouteRequestCoordinator<int>(
      load: (_, __) async {
        calls++;
        if (calls == 1) throw StateError('route unavailable');
        return 2;
      },
    );
    await expectLater(
      coordinator.resolve(origin, destination),
      throwsStateError,
    );
    expect(await coordinator.resolve(origin, destination), 2);
  });
}
