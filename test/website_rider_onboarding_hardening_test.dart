import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:circum/website/shared/rider_onboarding/application_policy.dart';

void main() {
  final valid = {
    'fullName': 'Test Rider',
    'phoneNumber': '07700900123',
    'postcode': 'SW1A 1AA',
    'homeAddress': 'Address',
    'vehicleType': 'Car',
    'vehicleRegistration': 'AB12 CDE'
  };
  test('minimum fields are required, documents and notes are optional', () {
    expect(riderApplicationError(valid), null);
    expect(riderApplicationError({...valid, 'notes': ''}), null);
    expect(riderApplicationError({...valid, 'homeAddress': ''}),
        'Enter your address.');
    for (final key in valid.keys) {
      expect(riderApplicationError({...valid, key: ''}), isNotNull);
    }
    expect(riderApplicationError({...valid, 'vehicleType': 'bicycle'}),
        'Choose Motorbike, Car or Van.');
  });
  test('canonical document identifiers match backend records', () {
    expect(riderDocumentKey('V5C'), 'registration_v5c');
    expect(riderDocumentKey('Insurance'), 'insurance');
    expect(riderDocumentKey('Identity'), 'identity');
  });
  test(
      'Rider form preserves address, canonical vehicle and visible backend errors',
      () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    final rider = source.substring(
        source.indexOf('class _RiderEnrollmentPortalState'),
        source.indexOf('class _RiderWorkspace'));
    expect(rider, contains("'homeAddress': _homeAddress.text.trim()"));
    expect(
        rider, contains("'vehicleType': _vehicle.text.trim().toLowerCase()"));
    expect(rider, contains('pickRiderDocument()'));
    expect(rider, contains('submitRiderDocumentTransport('));
    expect(rider, contains('_listenToRiderOnboarding'));
    expect(rider, isNot(contains("TextEditingController(text: 'Alex Rider')")));
    expect(rider, contains('finally {'));
  });
  test(
      'document streams survive earnings subscription and recovery stays backend-owned',
      () {
    final source =
        File('lib/website/shared/circum_website_app.dart').readAsStringSync();
    final earnings = source.substring(
        source.indexOf('  void _listenToRiderEarnings('),
        source.indexOf('  void _listenToRiderPerformance('));
    expect(earnings, isNot(contains('_onboardingDocumentsSub?.cancel()')));
    expect(earnings, isNot(contains('_onboardingProfileSub?.cancel()')));
    final access = source.substring(
        source.indexOf('  Future<bool> _allowRiderUser('),
        source.indexOf('  Future<Set<CircumRole>> _rolesForUser('));
    expect(access, contains("httpsCallable('verifyRiderAccountAccess')"));
    expect(access, contains("httpsCallable('updateRiderProfile')"));
    expect(access, contains('CircumRole.unknown'));
  });
}
