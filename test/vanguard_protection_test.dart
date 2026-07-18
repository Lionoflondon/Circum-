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

      expect(fields, {'vanguardEnabled': false});
      expect(check.passed, isTrue);
      expect(check.attemptCount, 0);
    });

    test('initial public fields do not expose Vanguard PIN secrets', () {
      final fields = VanguardProtection.initialFields(
        description: 'iPhone 15',
        random: Random(2),
      );

      expect(fields['vanguardEnabled'], isTrue);
      expect(
        (fields['vanguardProtection'] as Map)['matchedCategory'],
        'Consumer Electronics',
      );
      expect(fields.containsKey('collectionPin'), isFalse);
      expect(fields.containsKey('deliveryPin'), isFalse);
      expect(fields.containsKey('collectionPinAttemptCount'), isFalse);
      expect(fields.containsKey('deliveryPinAttemptCount'), isFalse);
      expect((fields['vanguardProtection'] as Map).containsKey('collectionPin'),
          isFalse);
      expect((fields['vanguardProtection'] as Map).containsKey('deliveryPin'),
          isFalse);
      expect(VanguardProtection.collectionPin(fields), isNull);
      expect(VanguardProtection.deliveryPin(fields), isNull);
    });

    test('server-supplied expected PIN verifies collection outcome', () {
      final check = VanguardProtection.verifyPin(
        enabled: true,
        expectedPin: '345678',
        enteredPin: '345678',
        attemptCount: 1,
        stage: 'collection',
      );

      expect(check.passed, isTrue);
      expect(check.attemptCount, 2);
      expect(check.flagForReview, isFalse);
    });

    test('wrong delivery PIN blocks delivery completion', () {
      final check = VanguardProtection.verifyPin(
        enabled: true,
        expectedPin: '654321',
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
