import 'package:circum/app/business/business_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Business address contract', () {
    test('account profile renders canonical address maps as customer text', () {
      final account = BusinessAccount.fromMap('business_1', {
        'businessName': 'Circum Studio',
        'businessAddressCanonical': {
          'formattedAddress': '124 City Road, London EC1V 2NX, United Kingdom',
          'addressLine1': '124 City Road',
          'city': 'London',
          'postcode': 'EC1V 2NX',
          'country': 'United Kingdom',
        },
        'defaultPickupAddresses': [
          {
            'formattedAddress':
                'Flat 4, 29 St Fillans Road, London SE6 1DQ, United Kingdom',
          },
        ],
      });

      expect(account.businessAddress,
          '124 City Road, London EC1V 2NX, United Kingdom');
      expect(
        account.defaultPickupAddress,
        'Flat 4, 29 St Fillans Road, London SE6 1DQ, United Kingdom',
      );
      expect(account.businessAddress, isNot(contains('{')));
      expect(account.defaultPickupAddress, isNot(contains('formattedAddress')));
    });

    test('delivery rows render canonical pickup and drop-off maps safely', () {
      final delivery = BusinessDelivery.fromMap('delivery_1', {
        'pickupAddress': {
          'addressLine1': '282 Lewisham High Street',
          'city': 'London',
          'postcode': 'SE13 6JZ',
        },
        'dropoffAddress': {
          'formattedAddress': '124 City Road, London EC1V 2NX, United Kingdom',
        },
      });

      expect(delivery.pickup, '282 Lewisham High Street');
      expect(
          delivery.dropoff, '124 City Road, London EC1V 2NX, United Kingdom');
      expect(delivery.pickup, isNot(contains('null')));
      expect(delivery.dropoff, isNot(contains('{')));
    });
  });
}
