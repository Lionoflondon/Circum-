import 'dart:io';

import 'package:circum/app/business/business_models.dart';
import 'package:circum/app/platform/address_engine.dart';
import 'package:circum/app/send_package/models/suggestions.m.dart';
import 'package:circum/app/sender_mobile/gift_journey_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cross-product canonical address authority', () {
    Suggestion flatPremiseSuggestion() => Suggestion(
      placeId: 'google-flat-4-29',
      description:
          'Flat 4, 29 St Fillans Road, London, SE6 1DQ, United Kingdom',
      mainText: 'Flat 4, 29 St Fillans Road',
      subText: 'London SE6 1DQ',
      lat: 51.4433135,
      lng: -0.0092425,
      components: const {
        'addressLine1': '29 St Fillans Road',
        'buildingNumber': '29',
        'street': 'St Fillans Road',
        'apartment': 'Flat 4',
        'city': 'London',
        'postcode': 'SE6 1DQ',
        'country': 'United Kingdom',
        'resolutionPrecision': 'unit',
      },
    );

    test('shared resolver payload preserves flat, premise and precision', () {
      final normalized = AddressEngine.normalize(
        suggestion: flatPremiseSuggestion(),
      );

      expect(normalized['buildingNumber'], '29');
      expect(normalized['apartment'], 'Flat 4');
      expect(normalized['street'], 'St Fillans Road');
      expect(normalized['postcode'], 'SE6 1DQ');
      expect(normalized['resolutionPrecision'], 'unit');
      expect(normalized['latitude'], 51.4433135);
      expect(normalized['longitude'], -0.0092425);
    });

    test('Gifts admin payload projects canonical premise fields', () {
      final draft = GiftJourneyDraft.forMode(SenderGiftMode.someone).copyWith(
        recipientName: 'Recipient',
        relationship: 'Friend',
        occasion: 'Birthday',
        deliveryAddress:
            'Flat 4, 29 St Fillans Road, London, SE6 1DQ, United Kingdom',
        deliveryAddressData: flatPremiseSuggestion(),
        deliveryDate: '2026-08-20',
        deliveryTimeWindow: 'Flexible',
        flexibleDelivery: true,
      );

      final payload = draft.adminReviewPayload(
        senderId: 'sender-1',
        senderEmail: 'sender@example.com',
      );
      final data = Map<String, dynamic>.from(
        payload['deliveryAddressData'] as Map,
      );
      final components = Map<String, dynamic>.from(data['components'] as Map);

      expect(payload['buildingNumber'], '29');
      expect(payload['apartment'], 'Flat 4');
      expect(payload['resolutionPrecision'], 'unit');
      expect(components['buildingNumber'], '29');
      expect(components['apartment'], 'Flat 4');
      expect(components['resolutionPrecision'], 'unit');
    });

    test('Business model preserves saved canonical address metadata', () {
      final account = BusinessAccount.fromMap('business-1', {
        'businessName': 'Circum Test Ltd',
        'contactEmail': 'ops@example.com',
        'billingEmail': 'billing@example.com',
        'businessAddress':
            'Flat 4, 29 St Fillans Road, London, SE6 1DQ, United Kingdom',
        'businessAddressData': AddressEngine.normalize(
          suggestion: flatPremiseSuggestion(),
        ),
        'defaultPickupAddresses': [
          'Flat 4, 29 St Fillans Road, London, SE6 1DQ, United Kingdom',
        ],
        'defaultPickupAddressData': [
          AddressEngine.normalize(suggestion: flatPremiseSuggestion()),
        ],
      });

      expect(account.businessAddressData['buildingNumber'], '29');
      expect(account.businessAddressData['apartment'], 'Flat 4');
      expect(account.businessAddressData['resolutionPrecision'], 'unit');
      expect(account.defaultPickupAddressData['buildingNumber'], '29');
      expect(account.defaultPickupAddressData['apartment'], 'Flat 4');
    });

    test('Health+ submits canonical pharmacy and delivery address data', () {
      final source = File(
        'lib/app/health_plus/view/health_plus.dart',
      ).readAsStringSync();

      expect(source, contains("'pharmacyAddressData': pharmacyAddressData"));
      expect(source, contains("'deliveryAddressData': deliveryAddressData"));
      expect(source, contains('selectedSuggestion'));
      expect(source, contains('AddressEngine.cleanSuggestion'));
      expect(source, contains('Choose a verified pharmacy address.'));
      expect(source, contains('Choose a verified delivery address.'));
    });
  });
}
