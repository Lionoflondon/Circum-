import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entering Send resets a terminal booking before mounting the canvas',
      () {
    final source = File(
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ).readAsStringSync();

    expect(source, contains("index == 1"));
    expect(source, contains("_index != 1"));
    expect(source, contains("_isTerminalBookingStatus("));
    expect(source,
        contains("_bookingBloc.add(const ResetSenderBookingSession())"));
    for (final status in const [
      'cancelled_by_sender',
      'delivered',
      'failed',
      'expired',
      'archived',
    ]) {
      expect(source, contains("'$status'"));
    }
  });

  test('terminal restoration is classified before any active-delivery watcher',
      () {
    final source = File(
      'lib/app/send_package/bloc/send_package_bloc.dart',
    ).readAsStringSync();

    final checkStart = source.indexOf(
      'void _handleCheckForActiveRequestEvent',
    );
    final checkEnd = source.indexOf(
      'void _handleSetPanelControlStatusEvent',
      checkStart,
    );
    final handler = source.substring(checkStart, checkEnd);

    expect(handler, contains('normalizedRequestStatus'));
    expect(handler, contains('_terminalRequestStatuses.contains'));
    expect(handler, contains('_clearTerminalRestoration(activeRequest)'));
    expect(
      handler.indexOf('_clearTerminalRestoration(activeRequest)'),
      lessThan(handler.indexOf('add(WatchActiveDelivery(')),
    );
  });
}
