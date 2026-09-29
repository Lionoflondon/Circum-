import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final bloc = File('lib/app/send_package/bloc/send_package_bloc.dart')
      .readAsStringSync();
  final api = File('lib/app/sender_mobile/sender_production_payment_api.dart')
      .readAsStringSync();

  test('QA capability is consulted before the live payment-mode route', () {
    expect(bloc, contains("'sender_capability'"));
    expect(bloc, contains("'sender_payment_session'"));
    expect(bloc, contains("'sender_finalize'"));
    expect(bloc, contains("'sender_read'"));
    expect(bloc.indexOf('_senderWebQaCapability()'),
        lessThan(bloc.indexOf("_callableMap('getSenderPaymentMode'")));
    expect(bloc, contains("if (qaCapability == null)"));
    expect(bloc, contains('Ordinary senders can still reach the live authority'));
    expect(bloc, contains('QA IDs'));
    expect(bloc, contains('} catch (_) {'));
    expect(bloc, isNot(contains('package:circum/website/')));
  });

  test('QA payment calls use the dedicated authenticated boundary', () {
    expect(api, contains("'sender_qa'"));
    expect(api, contains('circum-qa-special-flow-j2b7cicfwq-uc.a.run.app'));
    expect(api, contains("'X-Firebase-AppCheck': appCheckToken"));
    expect(api, contains("'Authorization': 'Bearer \$token'"));
  });
}
