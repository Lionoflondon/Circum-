import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web checkout finalization does not depend on ScreenUtil', () {
    final source = File(
      'lib/app/send_package/bloc/send_package_bloc.dart',
    ).readAsStringSync();
    final start = source.indexOf('void _handleFinalizeSenderWebCheckout(');
    final end = source.indexOf(
      'void _handleSendDeliveryRequestEvent(',
      start,
    );
    final handler = source.substring(start, end);

    expect(handler, isNot(contains('.sh')));
    expect(handler, contains("_callableMap('finalizeSenderWebCheckout'"));
    expect(handler, contains('add(WatchActiveDelivery(requestId: requestId))'));
  });
}
