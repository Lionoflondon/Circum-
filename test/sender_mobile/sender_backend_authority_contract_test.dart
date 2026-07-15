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

  test('Sender web delivery checkout uses canonical payment callables only',
      () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();

    expect(source, contains("httpsCallable('createSenderBookingQuote')"));
    expect(source, contains("httpsCallable('createSenderPaymentSession')"));
    expect(source, contains("httpsCallable('createSenderPaidDelivery')"));
    expect(source, isNot(contains('cloudfunctions.net/createPaymentIntent')));
    expect(
        source, isNot(contains('_completeSenderBookingPaymentTransaction(')));
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

  test('legacy Sender delivery path cannot create or delete delivery records',
      () {
    final legacyBloc = File('lib/app/send_package/bloc/send_package_bloc.dart')
        .readAsStringSync();

    expect(legacyBloc,
        isNot(contains('.collection("deliveryRequests").doc(user?.uid).set')));
    expect(
        legacyBloc,
        isNot(
            contains(".collection('deliveryRequests').doc(user.uid).delete")));
    expect(
        legacyBloc,
        isNot(contains(
            'DeliveryPricing.calculate(\n          DeliveryPricingInput')));
    expect(
        legacyBloc,
        contains(
            'Please continue with the secure booking flow to create this delivery.'));
    expect(legacyBloc, contains("httpsCallable('requestSenderCancellation')"));
  });

  test(
      'Sender cancellation uses canonical backend preview and execute callables',
      () {
    final tracking = File('lib/app/sender_mobile/sender_tracking_screen.dart')
        .readAsStringSync();
    final index = File('server/functions/index.js').readAsStringSync();
    final policy =
        File('server/functions/delivery-policy.js').readAsStringSync();

    expect(tracking, contains("'previewSenderCancellation'"));
    expect(tracking, contains("'requestSenderCancellation'"));
    expect(tracking, isNot(contains('getSenderCancellationQuote')));
    expect(tracking, isNot(contains('cancelSenderDelivery')));
    expect(tracking, isNot(contains('cancelDeliveryRequest')));
    expect(index, contains('exports.previewSenderCancellation'));
    expect(policy, contains('exports.previewSenderCancellation'));
    expect(policy, contains('core.cancellationDecision'));
  });

  test('Sender and support chat actions use the communication engine', () {
    final deliveryBloc =
        File('lib/app/send_package/bloc/send_package_bloc.dart')
            .readAsStringSync();
    final walletSupport =
        File('lib/app/send_package/view/ride_chats.dart').readAsStringSync();
    final supportBloc =
        File('lib/app/support/bloc/support_bloc.dart').readAsStringSync();
    final webSender = File('lib/web_sender_app.dart').readAsStringSync();
    final messaging = File('lib/messaging.dart').readAsStringSync();

    expect(deliveryBloc, contains("httpsCallable('sendCircumMessage')"));
    expect(deliveryBloc, isNot(contains("httpsCallable('sendMessage')")));
    expect(deliveryBloc, isNot(contains('ChatsHelper().storeChat')));

    expect(walletSupport,
        contains("httpsCallable('getOrCreateSupportConversation')"));
    expect(walletSupport, contains("httpsCallable('sendCircumMessage')"));
    expect(walletSupport, contains("httpsCallable('setConversationTyping')"));
    expect(walletSupport, contains("httpsCallable('markConversationRead')"));
    expect(
        walletSupport, isNot(contains("collection('supportTickets').doc()")));
    expect(
        walletSupport, isNot(contains("collection('chats').doc(chatId).set")));

    expect(supportBloc,
        contains("httpsCallable('getOrCreateSupportConversation')"));
    expect(supportBloc, contains("httpsCallable('sendCircumMessage')"));
    expect(supportBloc, isNot(contains("collection('messages').doc().set")));
    expect(supportBloc, isNot(contains('ChatsHelper().storeChat')));

    expect(webSender,
        contains("httpsCallable('updateSupportConversationStatus')"));
    expect(
        webSender, contains("httpsCallable('getOrCreateSupportConversation')"));
    expect(webSender, contains("httpsCallable('startAdminConversation')"));
    expect(webSender, contains("httpsCallable('sendCircumMessage')"));
    expect(webSender, isNot(contains("chatRef.collection('messages').add")));
    expect(
        webSender, isNot(contains("db.collection('chats').doc(chatId).set")));
    expect(messaging, isNot(contains('ChatsHelper().storeChat')));
  });

  test('legacy Rider web shell uses canonical backend authority only', () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    final riderShell = source.substring(
      source.indexOf('class _RiderEnrollmentPortalState'),
      source.indexOf('class _CustomerPortal'),
    );
    final customerPortal = source.substring(
      source.indexOf('class _CustomerPortal'),
      source.indexOf('class _DesktopPortalLayout'),
    );

    expect(
      riderShell,
      contains("_callLegacyRiderCallable('acceptRideRequests'"),
    );
    expect(
      riderShell,
      contains("_callLegacyRiderCallable('updateDeliveryTrackingStatus'"),
    );
    expect(
      riderShell,
      contains("_callLegacyRiderCallable('updateDeliveryLiveLocation'"),
    );
    expect(
      riderShell,
      contains("_callLegacyRiderCallable('reportWaitingContext'"),
    );
    expect(
      riderShell,
      contains("_callLegacyRiderCallable('markRiderNoShow'"),
    );
    expect(riderShell, contains("httpsCallable('sendCircumMessage')"));
    expect(riderShell, contains("httpsCallable('requestRiderWithdrawal')"));

    expect(riderShell, isNot(contains("'pickupNoShowSurchargeGbp': 5.0")));
    expect(riderShell,
        isNot(contains("'waitingSurchargeTotalGbp': FieldValue.increment")));
    expect(
        riderShell, isNot(contains("'pickupWaitExtensionChargeGbp': charge")));
    expect(riderShell,
        isNot(contains("db.collection('riderEarnings').doc(user.uid).set")));
    expect(riderShell,
        isNot(contains("db.collection('walletTransactions').doc('roth_")));
    expect(riderShell,
        isNot(contains("db.collection('riderWalletTransactions')")));
    expect(
        riderShell, isNot(contains(".collection('messages')\n        .add")));
    expect(riderShell, isNot(contains("'senderId': 'circum-system'")));
    expect(riderShell, isNot(contains("'matchingStatus': 'accepted'")));
    expect(riderShell,
        isNot(contains("'acceptedAt': FieldValue.serverTimestamp()")));
    expect(riderShell, isNot(contains("'status': 'sender_no_show_pickup'")));
    expect(riderShell, isNot(contains("collection('irisCorrections')")));
    expect(riderShell, isNot(contains("collection('irisDeliveryEstimates')")));
    expect(riderShell, isNot(contains('DeliveryPricing.calculate')));
    expect(riderShell, isNot(contains('VanguardProtection.verifyPin')));
    expect(customerPortal,
        isNot(contains("db.collection('riderEarnings').doc(driverId)")));
    expect(
        customerPortal,
        isNot(
            contains("db.collection('riderWalletTransactions').doc(tipTxId)")));
    expect(customerPortal,
        isNot(contains("Customer tip credited to rider available earnings.")));
  });

  test('backend exports canonical support conversation callables', () {
    final engine =
        File('server/functions/communication-engine.js').readAsStringSync();
    final index = File('server/functions/index.js').readAsStringSync();
    final contracts = File('docs/callable-contracts.md').readAsStringSync();

    expect(engine, contains('async function getOrCreateSupportConversation'));
    expect(engine, contains('async function updateSupportConversationStatus'));
    expect(engine, contains('conversationType: "support"'));
    expect(engine, contains('adminUnreadCount: isAdmin(context) ? 0'));
    expect(index, contains('exports.getOrCreateSupportConversation'));
    expect(index, contains('exports.updateSupportConversationStatus'));
    expect(contracts, contains('| Open support conversation |'));
    expect(contracts, contains('| Update support conversation status |'));
  });
}
