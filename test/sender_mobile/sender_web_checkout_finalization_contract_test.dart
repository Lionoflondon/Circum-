import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'web checkout finalization confirms payment before client housekeeping',
      () {
    final source = File(
      'lib/app/send_package/bloc/send_package_bloc.dart',
    ).readAsStringSync();
    final handlerStart = source.indexOf(
      'void _handleFinalizeSenderWebCheckout(',
    );
    final handlerEnd = source.indexOf(
      '    } on FirebaseFunctionsException catch (error)',
      handlerStart,
    );
    expect(handlerStart, greaterThanOrEqualTo(0));
    expect(handlerEnd, greaterThan(handlerStart));

    final handler = source.substring(handlerStart, handlerEnd);
    final successEmit = handler.indexOf('senderPaymentStatus: \'succeeded\'');
    final persistence = handler.indexOf(
      'active request persistence failed; payment remains confirmed',
    );

    expect(successEmit, greaterThanOrEqualTo(0));
    expect(persistence, greaterThan(successEmit));
    expect(
      handler,
      contains('active delivery watch failed; payment remains confirmed'),
    );
    expect(
      handler,
      contains('drawer update failed; payment remains confirmed'),
    );
  });

  test('sender web preview provides the auth bloc used by booking maps', () {
    final source = File(
      'lib/app/sender_mobile/sender_mobile_preview.dart',
    ).readAsStringSync();

    expect(source, contains('MultiBlocProvider('));
    expect(source, contains('BlocProvider<AuthBloc>'));
    expect(source, contains('AuthBloc()..add(SortSessionState())'));
    expect(source, contains('BlocProvider<SendPackageBloc>'));
  });
}
