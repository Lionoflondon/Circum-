import 'dart:io';

import 'package:circum/app/send_package/models/sender_delivery_restoration.dart';
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
      final ownershipStart = bloc.indexOf(
        'SenderRestorationRecord? _ownedRestorationRecord(',
      );
      final ownershipEnd = bloc.indexOf(
        'Stream<SenderRestorationRecord?> _watchActiveDeliveryRecord(',
        ownershipStart,
      );
      final ownershipGate = bloc.substring(ownershipStart, ownershipEnd);

      expect(ownershipGate, contains("data['senderId'] ?? data['userId']"));
      expect(ownershipGate, contains('ownerId != senderId'));
      expect(ownershipGate, contains('return null'));
      expect(
        bloc.indexOf('_ownedRestorationRecord(direct, senderId)'),
        lessThan(bloc.indexOf('_watchActiveDeliveryRecord(')),
      );
    },
  );

  test('sender cancellation is terminal in restoration and tracking', () {
    expect(
      SenderDeliveryRestorationPolicy.isTerminalStatus('cancelled_by_sender'),
      isTrue,
    );
    expect(tracking, contains("'cancelled_by_sender' ||"));
  });

  test('terminal delivery rendering cannot reattach live location', () {
    final dispositionCheck = bloc.indexOf(
      'restorationDisposition !=\n'
      '            SenderDeliveryRestorationDisposition.terminal',
    );
    final liveLocationStart = bloc.indexOf(
      'await _listenToActiveDeliveryLiveLocation(documentId)',
      dispositionCheck,
    );

    expect(dispositionCheck, isNonNegative);
    expect(liveLocationStart, greaterThan(dispositionCheck));
  });
}
