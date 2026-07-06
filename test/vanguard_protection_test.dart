import 'dart:math';

import 'package:circum/app/delivery_security/vanguard_protection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VanguardProtection', () {
    test('generates two separate 6-digit PINs', () {
      final pins = VanguardProtection.generatePins(random: Random(4));

      expect(pins.collectionPin, matches(RegExp(r'^\d{6}$')));
      expect(pins.deliveryPin, matches(RegExp(r'^\d{6}$')));
      expect(pins.collectionPin, isNot(pins.deliveryPin));
    });

    test('high-value item category automatically enables protection', () {
      expect(
        VanguardProtection.shouldEnable(description: 'iPhone 15 Pro'),
        isTrue,
      );
      expect(
        VanguardProtection.shouldEnable(description: 'MacBook laptop'),
        isTrue,
      );
      expect(
        VanguardProtection.shouldEnable(description: 'Gaming console'),
        isTrue,
      );
    });

    test('expanded protected category examples activate automatically', () {
      final protectedDescriptions = [
        'iPhone',
        'MacBook',
        'Diamond ring',
        'Rolex watch',
        'PlayStation 5',
        'Camera lens',
        'Designer handbag',
        'Racing bicycle',
        'Confidential business documents',
      ];

      for (final description in protectedDescriptions) {
        expect(
          VanguardProtection.shouldEnable(description: description),
          isTrue,
          reason: description,
        );
      }
    });

    test('IRIS or package category text can activate Vanguard', () {
      expect(
        VanguardProtection.shouldEnable(
          description: 'Parcel',
          packageType: 'Professional photography equipment',
        ),
        isTrue,
      );
      expect(
        VanguardProtection.matchedCategoryName(
          description: 'Parcel',
          packageType: 'Professional photography equipment',
        ),
        'Sports and Hobby Equipment',
      );
    });

    test('manual high-value selection activates protection', () {
      expect(
        VanguardProtection.shouldEnable(
          description: 'Unlisted item',
          manuallySelected: true,
        ),
        isTrue,
      );
    });

    test('declared value above threshold enables protection', () {
      expect(
        VanguardProtection.shouldEnable(
          description: 'Artwork',
          declaredValueGbp: vanguardHighValueThresholdGbp + 1,
        ),
        isTrue,
      );
    });

    test('normal non-Vanguard delivery remains unchanged', () {
      final fields = VanguardProtection.initialFields(
        description: 'Small envelope',
        random: Random(1),
      );
      final check = VanguardProtection.verifyPin(
        enabled: false,
        expectedPin: null,
        enteredPin: '',
        attemptCount: 0,
        stage: 'collection',
      );

      expect(fields['vanguardEnabled'], false);
      expect(fields['vanguardProtocolEnabled'], false);
      expect(fields['vanguardStatus'], 'not_required');
      expect(check.passed, isTrue);
      expect(check.attemptCount, 0);
    });

    test('toggle enables Vanguard delivery protocol state', () {
      final fields = VanguardProtection.initialFields(
        description: 'Small envelope',
        manuallySelected: true,
        random: Random(7),
      );

      expect(fields['vanguardEnabled'], isTrue);
      expect(fields['vanguardProtocolEnabled'], isTrue);
      expect(fields['vanguardStatus'], 'pickup_verification_pending');
      expect(fields['vanguardVerificationState'], {
        'pickup': 'pending',
        'custody': 'pending',
        'handover': 'pending',
      });
      expect(fields['vanguardAuditTrail'], isNotEmpty);
      expect((fields['vanguardProtocol'] as Map)['timeline'],
          VanguardProtection.protocolTimeline);
    });

    test('IRIS can require Vanguard and sender cannot remove protocol', () {
      final decision = VanguardProtection.decideProtocol(
        description: 'Passport',
        irisRequired: true,
        irisRequiredReason: 'IRIS policy requires Vanguard for passports.',
      );
      final fields = VanguardProtection.initialFields(
        description: 'Passport',
        irisRequired: true,
        irisRequiredReason: 'IRIS policy requires Vanguard for passports.',
        random: Random(8),
      );

      expect(decision.required, isTrue);
      expect(decision.enabled, isTrue);
      expect(fields['vanguardProtocolEnabled'], isTrue);
      expect(fields['vanguardRequiredReason'],
          'IRIS policy requires Vanguard for passports.');
      expect((fields['vanguardProtocol'] as Map)['required'], isTrue);
    });

    test('pickup and drop-off are blocked until protocol milestones complete',
        () {
      final pending = {
        'vanguardProtocolEnabled': true,
        'vanguardStatus': 'pickup_verification_pending',
      };
      final custody = {
        'vanguardProtocolEnabled': true,
        'vanguardStatus': 'secure_custody',
      };
      final handoverPending = {
        'vanguardProtocolEnabled': true,
        'vanguardStatus': 'handover_pending',
      };
      final handoverVerified = {
        'vanguardProtocolEnabled': true,
        'vanguardStatus': 'handover_verified',
      };

      expect(VanguardProtection.canCompletePickup(pending), isFalse);
      expect(VanguardProtection.canCompletePickup(custody), isTrue);
      expect(VanguardProtection.canCompleteDropoff(handoverPending), isFalse);
      expect(VanguardProtection.canCompleteDropoff(handoverVerified), isTrue);
    });

    test('receipt reflects protocol completion and fee', () {
      final receipt = VanguardProtection.receiptSummary({
        'vanguardProtocolEnabled': true,
        'vanguardStatus': 'completed',
        'collectionPinVerified': true,
        'deliveryPinVerified': true,
      });

      expect(receipt['label'], 'Vanguard Protection');
      expect(receipt['protocolCompleted'], isTrue);
      expect(receipt['verificationCompleted'], isTrue);
      expect(receipt['fee'], 1.99);
    });

    test('wrong collection PIN blocks completion and increments attempts', () {
      final fields = VanguardProtection.initialFields(
        description: 'iPhone 15',
        random: Random(2),
      );
      final pin = VanguardProtection.collectionPin(fields);
      final check = VanguardProtection.verifyPin(
        enabled: true,
        expectedPin: pin,
        enteredPin: '000000',
        attemptCount: 0,
        stage: 'collection',
      );

      expect(fields['vanguardEnabled'], isTrue);
      expect(
        (fields['vanguardProtection'] as Map)['matchedCategory'],
        'Consumer Electronics',
      );
      expect(check.passed, isFalse);
      expect(check.attemptCount, 1);
      expect(check.errorMessage, contains('Incorrect collection PIN'));
    });

    test('correct collection PIN updates verification outcome', () {
      final fields = VanguardProtection.initialFields(
        description: 'Camera body',
        random: Random(3),
      );
      final pin = VanguardProtection.collectionPin(fields);
      final check = VanguardProtection.verifyPin(
        enabled: true,
        expectedPin: pin,
        enteredPin: pin!,
        attemptCount: 1,
        stage: 'collection',
      );

      expect(check.passed, isTrue);
      expect(check.attemptCount, 2);
      expect(check.flagForReview, isFalse);
    });

    test('wrong delivery PIN blocks delivery completion', () {
      final fields = VanguardProtection.initialFields(
        description: 'Jewellery parcel',
        random: Random(5),
      );
      final pin = VanguardProtection.deliveryPin(fields);
      final check = VanguardProtection.verifyPin(
        enabled: true,
        expectedPin: pin,
        enteredPin: '123123',
        attemptCount: 0,
        stage: 'delivery',
      );

      expect(check.passed, isFalse);
      expect(check.errorMessage, contains('Incorrect delivery PIN'));
    });

    test('too many failed attempts flags order for review', () {
      final check = VanguardProtection.verifyPin(
        enabled: true,
        expectedPin: '654321',
        enteredPin: '123456',
        attemptCount: vanguardMaxPinAttemptsBeforeReview - 1,
        stage: 'delivery',
      );

      expect(check.passed, isFalse);
      expect(check.flagForReview, isTrue);
    });
  });
}
