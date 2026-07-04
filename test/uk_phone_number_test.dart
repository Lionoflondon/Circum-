import 'package:circum/app/rider_profiles/uk_phone_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UkPhoneNumber', () {
    test('normalizes UK mobile formats to E.164 without truncation', () {
      expect(
        UkPhoneNumber.normalizeToE164('07891362527'),
        '+447891362527',
      );
      expect(
        UkPhoneNumber.normalizeToE164('7891362527'),
        '+447891362527',
      );
      expect(
        UkPhoneNumber.normalizeToE164('+447891362527'),
        '+447891362527',
      );
    });

    test('keeps sender receiver phone input intact before saving', () {
      const receiverPhoneTypedWithLeadingZero = '07891362527';
      const receiverPhoneTypedWithoutLeadingZero = '7891362527';

      expect(
        UkPhoneNumber.normalizeToE164(receiverPhoneTypedWithLeadingZero),
        '+447891362527',
      );
      expect(
        UkPhoneNumber.normalizeToE164(receiverPhoneTypedWithoutLeadingZero),
        '+447891362527',
      );
    });

    test('rejects invalid UK mobile numbers instead of cutting digits', () {
      expect(UkPhoneNumber.normalizeToE164('0789136252'), isNull);
      expect(UkPhoneNumber.normalizeToE164('078913625271'), isNull);
      expect(UkPhoneNumber.normalizeToE164('not a phone'), isNull);
    });
  });
}
