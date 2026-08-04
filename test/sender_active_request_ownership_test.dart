import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final bloc = File(
    'lib/app/send_package/bloc/send_package_bloc.dart',
  ).readAsStringSync();
  final tracking = File(
    'lib/app/sender_mobile/sender_tracking_screen.dart',
  ).readAsStringSync();

  test(
    'cached active delivery is restored only for its authenticated sender',
    () {
      final handlerStart = bloc.indexOf(
        'void _handleCheckForActiveRequestEvent(',
      );
      final handlerEnd = bloc.indexOf(
        'void _handleSetPanelControlStatusEvent(',
        handlerStart,
      );
      final handler = bloc.substring(handlerStart, handlerEnd);

      final ownershipCheck = handler.indexOf('senderId != user.uid');
      final listenerStart = handler.indexOf('add(WatchActiveDelivery(');
      expect(ownershipCheck, isNonNegative);
      expect(listenerStart, greaterThan(ownershipCheck));
      expect(handler, contains("prefs.remove('activeRequest')"));
      expect(handler, contains('activeDeliveryData: const {}'));
    },
  );

  test('sender cancellation is terminal in restoration and tracking', () {
    expect(bloc, contains("'cancelled_by_sender'"));
    expect(tracking, contains("'cancelled_by_sender' ||"));
  });
}
