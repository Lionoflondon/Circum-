import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final canvas = File(
    'lib/app/sender_mobile/sender_booking_canvas.dart',
  ).readAsStringSync();
  final bloc = File(
    'lib/app/send_package/bloc/send_package_bloc.dart',
  ).readAsStringSync();

  test('queued draft restores before backend draft retrieval', () {
    final loader = canvas.substring(
      canvas.indexOf('Future<void> _loadBackendDraft'),
      canvas.indexOf('void _hydrateRestoredDraft'),
    );
    expect(
      loader.indexOf('_restoreQueuedLocalDraft'),
      lessThan(loader.indexOf("'loadSenderDraft'")),
    );
    expect(loader, contains('setState(() => _draftLoading = false)'));
    expect(loader, contains('if (restoredLocally) return'));
  });

  test('route preview failure preserves locally calculated checkout route', () {
    expect(bloc, contains('_senderRoutePreviewTimeout'));
    expect(bloc, contains('.timeout(_senderRoutePreviewTimeout)'));
    expect(
      RegExp(
        'sourceAndDestinationStatus: SourceAndDestinationStatus.selected',
      ).allMatches(bloc).length,
      greaterThanOrEqualTo(3),
    );
    expect(bloc, contains('add(CalculateDistance())'));
    expect(bloc, contains('add(SetPrice())'));
    for (final event in [
      'route_start',
      'route_success',
      'route_failure',
      'route_timeout',
      'pricing_start',
      'pricing_success',
      'pricing_failure',
    ]) {
      expect(bloc, contains("'$event'"));
    }
    expect(bloc, isNot(contains('sender_flow payload=')));
  });

  test(
    'checkout does not advertise unverified scheduling or wallet default',
    () {
      expect(
        canvas,
        isNot(
          contains('Scheduled deliveries depend on Circum Rider availability'),
        ),
      );
      expect(
        canvas,
        isNot(contains("Apple Pay\${option.isDefault ? ' · Default' : ''}")),
      );
    },
  );
}
