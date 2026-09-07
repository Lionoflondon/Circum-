import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final businessRepository =
      File('lib/app/business/business_repository.dart').readAsStringSync();
  final businessView =
      File('lib/app/business/business_view.dart').readAsStringSync();
  final wallet =
      File('lib/app/sender_mobile/sender_wallet.dart').readAsStringSync();
  final chat =
      File('lib/app/send_package/view/ride_chats.dart').readAsStringSync();
  final authBloc =
      File('lib/app/authentication/bloc/auth_bloc.dart').readAsStringSync();
  final signIn =
      File('lib/app/authentication/view/signin_form.dart').readAsStringSync();

  test('native Business Roth uses authoritative bounded checkout', () {
    expect(businessRepository,
        contains("httpsCallable('createBusinessRothCheckout')"));
    expect(businessRepository, contains("'idempotencyKey': requestKey"));
    expect(businessRepository, contains('businessOperationTimeout'));
    expect(businessView, contains("label: 'Buy Roth'"));
    expect(businessView, contains('createRothCheckout('));
    expect(businessView, contains('AppLifecycleState.resumed'));
  });

  test('Business core loads before optional request history', () {
    final core = businessRepository
        .indexOf('Future<BusinessWorkspaceData> loadWorkspace');
    final history = businessRepository
        .indexOf('Future<BusinessRequestHistory> loadRequestHistory');
    expect(core, greaterThanOrEqualTo(0));
    expect(history, greaterThan(core));
    expect(businessRepository, contains('.limit(25)'));
    expect(businessView, contains('unawaited(_loadRequestHistory(selected))'));
  });

  test('wallet never fabricates zero on network failure', () {
    expect(wallet, isNot(contains('_wallet ??= const SenderWalletData')));
    expect(wallet, contains('Your Roth balance is unavailable'));
    expect(wallet, contains('Showing your last saved wallet'));
  });

  test('chat open and send operations terminate on timeout', () {
    expect(chat, contains('_chatOperationTimeout'));
    expect(chat, contains('Message timed out. Your text is preserved'));
    expect(chat,
        contains("actionLabel: widget.supportConversation ? 'Retry' : 'Back'"));
  });

  test('sign-in spinner follows canonical auth status', () {
    expect(
        signIn, contains('state.status == Status.loading || state.isLoading'));
  });

  test('auth bootstrap avoids a duplicate canonical profile read', () {
    final start = authBloc.indexOf('Future<String?> _hydrateSenderSession(');
    final end = authBloc.indexOf(
        'Future<String?> _hydrateSenderSessionRecoverably', start);
    final body = authBloc.substring(start, end);
    expect(body, contains('ensureCanonicalSenderAccount'));
    expect(body, isNot(contains('authority.load(')));
  });
}
