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
    final senderActivitySource =
        File('lib/app/sender_mobile/sender_activity.dart').readAsStringSync();
    final sendPackageSource =
        File('lib/app/send_package/bloc/send_package_bloc.dart')
            .readAsStringSync();
    final supportSource =
        File('lib/app/support/bloc/support_bloc.dart').readAsStringSync();

    expect(senderSource, contains('senderTrackingStateForBackendData'));
    expect(senderSource, contains('proofOfDeliveryFromRecord'));
    expect(senderActivitySource, contains('trackingTimeline'));
    expect(
        senderSource, contains("httpsCallable('getDeliveryEvidenceAccess')"));
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
    expect(adminSource, contains("httpsCallable('getDeliveryEvidenceAccess')"));
    expect(adminSource, contains('trackingTimeline'));
    expect(adminSource,
        isNot(contains("collection('deliveryRequests').doc(id).set")));
  });

  test('Shared hosted proof panel resolves canonical evidence through backend',
      () {
    final sharedSource =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();

    expect(sharedSource, contains('proofOfDeliveryFromRecord'));
    expect(sharedSource, contains("httpsCallable('recordDeliveryEvidence')"));
    expect(
        sharedSource, contains("httpsCallable('getDeliveryEvidenceAccess')"));
  });

  test('ETA displays do not invent operational timing locally', () {
    final senderSource =
        File('lib/app/sender_mobile/sender_tracking_screen.dart')
            .readAsStringSync();
    final sharedSource =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    final adminSource =
        File('lib/app/admin/admin_phase1_shell.dart').readAsStringSync();

    expect(senderSource, contains('senderCanonicalEtaForBackendData'));
    expect(senderSource, contains('Updating ETA'));
    for (final hardcoded in [
      'Usually under 6 min',
      "eta: '7 min'",
      "eta: '4 min'",
      "eta: '18 min'",
      "eta: '11 min'",
      "eta: '< 3 min'",
    ]) {
      expect(senderSource, isNot(contains(hardcoded)));
    }

    expect(sharedSource, isNot(contains('remainingMiles / 18 * 60')));
    expect(sharedSource, contains("label: 'ETA'"));
    expect(sharedSource, contains("value: 'Updating ETA'"));

    expect(adminSource, contains('_adminDeliveryEta'));
    expect(adminSource, isNot(contains("('ETA', delivery['eta']")));
  });
}
