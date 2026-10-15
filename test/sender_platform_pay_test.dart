import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circum/app/sender_mobile/sender_platform_pay.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final mode in ['test', 'live']) {
      test('$platform probes the $mode wallet realm', () async {
        var calls = 0;
        final supported = await senderDeviceWalletSupported(
          platform: platform,
          isWeb: false,
          environment: mode,
          publishableKey: 'pk_${mode}_synthetic',
          probe: (params) async {
            calls++;
            expect(params.testEnv, mode == 'test');
            return true;
          },
        );
        expect(supported, isTrue);
        expect(calls, 1);
      });
    }
  }
  test('mismatched Stripe realm never invokes a device wallet', () async {
    var calls = 0;
    await expectLater(
        senderDeviceWalletSupported(
          platform: TargetPlatform.android,
          isWeb: false,
          environment: 'live',
          publishableKey: 'pk_test_synthetic',
          probe: (_) async {
            calls++;
            return true;
          },
        ),
        throwsFormatException);
    expect(calls, 0);
  });
  test('web and unsupported surfaces never invoke native Stripe', () async {
    for (final target in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux
    ]) {
      expect(
          await senderDeviceWalletSupported(
            platform: target,
            isWeb: true,
            probe: (_) async => throw StateError('Native SDK called'),
          ),
          isFalse);
    }
    expect(
        await senderDeviceWalletSupported(
          platform: TargetPlatform.linux,
          isWeb: false,
          probe: (_) async => throw StateError('Native SDK called'),
        ),
        isFalse);
  });
  test('device refusal and SDK failure never become supported', () async {
    expect(
        await senderDeviceWalletSupported(
          platform: TargetPlatform.android,
          isWeb: false,
          environment: 'test',
          publishableKey: 'pk_test_synthetic',
          probe: (_) async => false,
        ),
        isFalse);
    await expectLater(
        senderDeviceWalletSupported(
          platform: TargetPlatform.android,
          isWeb: false,
          environment: 'test',
          publishableKey: 'pk_test_synthetic',
          probe: (_) async => throw StateError('SDK failure'),
        ),
        throwsStateError);
  });
}
