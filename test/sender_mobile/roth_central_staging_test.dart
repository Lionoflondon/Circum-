import 'package:flutter_test/flutter_test.dart';
import 'package:circum/app/sender_mobile/roth_central_staging_gate.dart';

void main() {
  group('ROTH central staging app gate', () {
    test(
      'requires enabled flag and exact explicitly configured staging project',
      () {
        expect(
          rothCentralStagingEnabledFor(
            firebaseProjectId: 'circum-sender-stg',
            enabled: true,
            configuredProjectId: 'circum-sender-stg',
          ),
          isTrue,
        );
        expect(
          rothCentralStagingEnabledFor(
            firebaseProjectId: 'circum-sender-stg',
            enabled: false,
            configuredProjectId: 'circum-sender-stg',
          ),
          isFalse,
        );
        expect(
          rothCentralStagingEnabledFor(
            firebaseProjectId: 'circum-2797c',
            enabled: true,
            configuredProjectId: 'circum-sender-stg',
          ),
          isFalse,
        );
      },
    );

    test(
      'rejects production and project names without an explicit staging marker',
      () {
        expect(
          rothCentralStagingEnabledFor(
            firebaseProjectId: 'circum-2797c',
            enabled: true,
            configuredProjectId: 'circum-2797c',
          ),
          isFalse,
        );
        expect(
          rothCentralStagingEnabledFor(
            firebaseProjectId: 'circum-qa',
            enabled: true,
            configuredProjectId: 'circum-qa',
          ),
          isFalse,
        );
        expect(
          rothCentralStagingEnabledFor(
            firebaseProjectId: 'circum-sender-stg',
            enabled: true,
            configuredProjectId: 'circum-other-stg',
          ),
          isFalse,
        );
      },
    );
  });
}
