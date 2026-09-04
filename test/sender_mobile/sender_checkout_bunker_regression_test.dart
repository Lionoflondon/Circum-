import 'dart:io';

import 'package:circum/app/sender_mobile/sender_booking_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persisted route coordinates remain quote-ready after engine restore',
      () {
    const complete = SenderBookingDraft(
      pickupLat: 51.5074,
      pickupLng: -0.1278,
      dropoffLat: 51.5155,
      dropoffLng: -0.0922,
    );
    const incomplete = SenderBookingDraft(
      pickupLat: 51.5074,
      pickupLng: -0.1278,
      dropoffLat: 51.5155,
    );

    expect(complete.hasCompleteRouteCoordinates, isTrue);
    expect(incomplete.hasCompleteRouteCoordinates, isFalse);
  });

  final canvas = File(
    'lib/app/sender_mobile/sender_booking_canvas.dart',
  ).readAsStringSync();
  final bloc = File(
    'lib/app/send_package/bloc/send_package_bloc.dart',
  ).readAsStringSync();

  test('cleared or invalidated quotes are eligible for a same-route retry', () {
    expect(
      senderQuoteRequestNeeded(
        lastRequestKey: 'route-a',
        requestKey: 'route-a',
        quoteId: null,
        quoteTotal: null,
        quoteError: '',
      ),
      isTrue,
    );
    expect(
      senderQuoteRequestNeeded(
        lastRequestKey: 'route-a',
        requestKey: 'route-a',
        quoteId: 'quote-1',
        quoteTotal: 12.50,
        quoteError: '',
      ),
      isFalse,
    );
    expect(canvas, contains('senderQuoteRequestNeeded('));
  });

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

  test('unresolved manual addresses cannot advance into quote generation', () {
    expect(
      canvas,
      contains('Select an address from the suggestions to continue.'),
    );
    expect(
      canvas,
      contains(
          'final buttonEnabled = !isResolvingTypedAddress && canContinue;'),
    );
    expect(
      canvas,
      contains('canContinue: engine.pickupCoordinate != null ||'),
    );
    expect(
      canvas,
      contains('canContinue: engine.desinationCoordinate != null ||'),
    );
    expect(
      canvas,
      isNot(contains('canContinue || typedAddressCanContinue')),
    );
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
