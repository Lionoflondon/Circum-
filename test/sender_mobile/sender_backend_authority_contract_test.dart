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
    expect(canvas, contains("'baseRevision': _draftRevision"));
    expect(canvas, contains('senderBookingDraftQueue:'));
    expect(canvas, contains('Updated from another device'));
    expect(canvas, contains('Restoring delivery'));
    expect(state, contains('toBackendDraftPayload'));
    expect(state, contains('fromBackendDraft'));
    expect(functions, contains('revision: nextRevision'));
    expect(functions, contains('db.runTransaction'));
    expect(functions, contains('expiresAt: draftExpiresAt()'));
    expect(functions, contains('cleanupExpiredSenderDrafts'));
    expect(functions, contains('DRAFT_RETENTION_DAYS = 30'));
    expect(functions, contains('senderBookingDrafts'));
    expect(functions, contains('exports.saveSenderDraft'));
    expect(functions, contains('exports.loadSenderDraft'));
    expect(functions, contains('exports.deleteSenderDraft'));
    expect(rules, contains('match /senderBookingDrafts/{uid}'));
    expect(rules,
        contains('allow read: if signedIn() && uid == request.auth.uid;'));
    expect(rules, contains('allow create, update, delete: if false;'));
  });

  test('paid Sender delivery creation is idempotent by draft and payment', () {
    final canvas = File('lib/app/sender_mobile/sender_booking_canvas.dart')
        .readAsStringSync();
    final functions =
        File('server/functions/sender-booking.js').readAsStringSync();

    expect(canvas, contains("'idempotencyKey':"));
    expect(functions, contains('senderDeliveryIdempotency'));
    expect(functions, contains(r'stableId(`${sender.uid}:${draftId'));
    expect(functions, contains('idempotent: true'));
  });
}
