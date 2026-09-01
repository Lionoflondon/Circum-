import 'package:circum/app/sender_mobile/sender_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sender canonical first name', () {
    test('trims signup input without changing the entered name', () {
      expect(normalizeSenderFirstName('  Jason  '), 'Jason');
      expect(
        normalizeSenderFirstName("  Anne-Marie O'Neil  "),
        "Anne-Marie O'Neil",
      );
      expect(normalizeSenderFirstName('   '), isEmpty);
    });
  });

  group('Sender local-time greeting', () {
    test('uses the required local morning boundary', () {
      expect(
        senderGreetingForLocalTime(DateTime(2026, 9, 1, 4, 59)),
        'Good evening',
      );
      expect(
        senderGreetingForLocalTime(DateTime(2026, 9, 1, 5)),
        'Good morning',
      );
      expect(
        senderGreetingForLocalTime(DateTime(2026, 9, 1, 11, 59)),
        'Good morning',
      );
    });

    test('uses the required local afternoon and evening boundaries', () {
      expect(
        senderGreetingForLocalTime(DateTime(2026, 9, 1, 12)),
        'Good afternoon',
      );
      expect(
        senderGreetingForLocalTime(DateTime(2026, 9, 1, 16, 59)),
        'Good afternoon',
      );
      expect(
        senderGreetingForLocalTime(DateTime(2026, 9, 1, 17)),
        'Good evening',
      );
    });

    test('never invents a missing name', () {
      expect(
        senderGreeting(localTime: DateTime(2026, 9, 1, 20), firstName: ''),
        'Good evening',
      );
      expect(
        senderGreeting(
          localTime: DateTime(2026, 9, 1, 20),
          firstName: ' Jason ',
        ),
        'Good evening, Jason',
      );
    });
  });
}
