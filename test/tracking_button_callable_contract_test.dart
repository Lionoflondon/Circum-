import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Rider tracking controls remain connected to backend callables', () {
    final riderSource =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();

    final acceptStart = riderSource.indexOf('Future<void> _acceptDeliveryJob');
    final acceptEnd = riderSource.indexOf(
      'void _syncRiderLiveLocationPublishing',
      acceptStart,
    );
    expect(acceptStart, isNonNegative);
    expect(acceptEnd, greaterThan(acceptStart));
    final acceptSource = riderSource.substring(acceptStart, acceptEnd);
    expect(acceptSource, contains("httpsCallable('acceptRideRequests')"));
    expect(acceptSource, isNot(contains("collection('deliveryRequests')")));

    final lifecycleStart =
        riderSource.indexOf('Future<void> _updateAcceptedJobStatus');
    final lifecycleEnd = riderSource.indexOf(
      'Future<Map<String, dynamic>?> _collectVanguardPinVerification',
      lifecycleStart,
    );
    expect(lifecycleStart, isNonNegative);
    expect(lifecycleEnd, greaterThan(lifecycleStart));
    final lifecycleSource = riderSource.substring(lifecycleStart, lifecycleEnd);
    expect(
      lifecycleSource,
      contains("httpsCallable('updateDeliveryTrackingStatus')"),
    );
    expect(lifecycleSource, isNot(contains("collection('riderEarnings')")));
    expect(lifecycleSource, isNot(contains("runTransaction")));

    expect(
      riderSource,
      contains("httpsCallable('updateDeliveryLiveLocation')"),
    );
    expect(
      riderSource,
      contains("FirebaseFunctions.instanceFor(region: 'us-central1')"),
    );
    expect(riderSource, contains("httpsCallable('reportLoadDiscrepancy')"));
    expect(riderSource, contains("httpsCallable('recordDeliveryEvidence')"));
    expect(lifecycleSource, isNot(contains("'photoUrl'")));
  });

  test('Sender tracking controls remain connected to backend actions', () {
    final senderSource =
        File('lib/app/sender_mobile/sender_tracking_screen.dart')
            .readAsStringSync();
    final sendPackageSource =
        File('lib/app/send_package/bloc/send_package_bloc.dart')
            .readAsStringSync();
    final supportSource =
        File('lib/app/support/bloc/support_bloc.dart').readAsStringSync();

    expect(senderSource, contains('senderTrackingStateForBackendData'));
    expect(senderSource, contains('proofOfDeliveryFromRecord'));
    expect(senderSource, contains("requestSenderCancellation"));
    expect(sendPackageSource,
        contains("httpsCallable('requestSenderCancellation')"));
    expect(
      supportSource,
      contains("httpsCallable('getOrCreateSupportConversation')"),
    );
  });

  test('Admin tracking and intervention controls use protected callables', () {
    final adminSource =
        File('lib/app/admin/admin_phase1_shell.dart').readAsStringSync();
    final adminRootSource =
        File('lib/app/admin/admin_root.dart').readAsStringSync();

    expect(adminSource, contains("httpsCallable('adminGovernanceAction')"));
    expect(
        adminSource, contains("httpsCallable('adminUpdateDeliveryOperation')"));
    expect(adminSource, contains("httpsCallable('resolveStaleDeliveryLock')"));
    expect(
        adminRootSource, contains("httpsCallable('reviewDeliveryAdjustment')"));
    expect(adminSource, contains("httpsCallable('adminRecordAuditEntry')"));
    expect(adminSource,
        isNot(contains("collection('deliveryRequests').doc(id).set")));
  });
}
