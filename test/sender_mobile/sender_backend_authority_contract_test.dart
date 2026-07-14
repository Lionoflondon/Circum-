import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authenticated Sender opens the canonical backend-backed surface', () {
    final source = File('lib/app.dart').readAsStringSync();

    expect(
      source,
      contains('return const SenderMobileHome(initialAuthenticated: true);'),
    );
    expect(
        source, isNot(contains("import 'app/bottom_nav/view/app_nav.dart'")));
    expect(source, isNot(contains('return AppNavView();')));
  });

  test('unused fake auth repository is retired', () {
    expect(File('lib/app/authentication/repo/auth_repo.dart').existsSync(),
        isFalse);
  });

  test('canonical Sender flow uses backend quote, payment and delivery calls',
      () {
    final source = File('lib/app/send_package/bloc/send_package_bloc.dart')
        .readAsStringSync();

    expect(source, contains("'createSenderBookingQuote'"));
    expect(source, contains("'createSenderPaymentSession'"));
    expect(source, contains("'createSenderPaidDelivery'"));
  });

  test('Sender delivery drafts persist through backend callables only', () {
    final canvas = File('lib/app/sender_mobile/sender_booking_canvas.dart')
        .readAsStringSync();
    final state = File('lib/app/sender_mobile/sender_booking_state.dart')
        .readAsStringSync();
    final functions =
        File('server/functions/sender-booking.js').readAsStringSync();
    final rules = File('firestore.rules').readAsStringSync();

    expect(canvas, contains("'loadSenderDraft'"));
    expect(canvas, contains("'saveSenderDraft'"));
    expect(canvas, contains("'deleteSenderDraft'"));
    expect(canvas, contains('Restoring delivery'));
    expect(state, contains('toBackendDraftPayload'));
    expect(state, contains('fromBackendDraft'));
    expect(functions, contains('senderBookingDrafts'));
    expect(functions, contains('exports.saveSenderDraft'));
    expect(functions, contains('exports.loadSenderDraft'));
    expect(functions, contains('exports.deleteSenderDraft'));
    expect(rules, contains('match /senderBookingDrafts/{uid}'));
    expect(rules, contains('allow create, update, delete: if false;'));
  });
}
