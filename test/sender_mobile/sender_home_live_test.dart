import 'dart:io';

import 'package:circum/app/sender_mobile/sender_mobile_home.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical delivery data becomes a Home recent order', () {
    final order = SenderHomeOrder.fromFirestore('delivery-1', {
      'parcel': {'itemName': 'Apple iPhone'},
      'pickupDetails': {'locality': 'Heathrow'},
      'dropoffDetails': {'locality': 'Westminster'},
      'status': 'arrived_at_pickup',
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 7, 10)),
    });

    expect(order.id, 'delivery-1');
    expect(order.title, 'Apple iPhone');
    expect(order.route, 'Heathrow → Westminster');
    expect(order.status, 'At pickup');
    expect(order.rawStatus, 'arrived_at_pickup');
  });

  test('missing delivery values never render literal null', () {
    final order = SenderHomeOrder.fromFirestore('delivery-2', {
      'pickupDetails': {'address': null},
      'dropoffDetails': {'address': '10 Downing Street'},
      'deliveryStatus': 'in_transit',
    });

    expect(order.title, 'Delivery');
    expect(order.route, '10 Downing Street');
    expect(order.route.toLowerCase(), isNot(contains('null')));
    expect(order.status, 'In transit');
  });

  test('Home uses authenticated live services and has resilient states', () {
    final source = File(
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ).readAsStringSync();

    expect(source, contains("collection('users').doc(user.uid)"));
    expect(source, contains("collection('deliveryRequests')"));
    expect(source, contains("collection('notifications')"));
    expect(source, contains("collection('healthPlusProfiles')"));
    expect(source, contains("collection('businessAccounts')"));
    expect(source, contains('builder: (_) => const BusinessAccessView()'));
    expect(source, contains("collection('giftRequests')"));
    expect(source, contains('SenderWalletHomeSummary'));
    expect(source, contains('Loading recent orders…'));
    expect(source, contains('No recent deliveries.'));
    expect(source, contains("'cancelled'"));
    expect(source, contains('Active conversation'));
    expect(source, contains('Ready when you are.'));
    expect(source, contains('Recent orders could not load.'));
    expect(source, contains('Recent orders are unavailable offline.'));
    expect(source, isNot(contains("title: 'Passport'")));
    expect(source, isNot(contains("title: 'Prescription collection'")));
  });

  test('existing Home destinations remain canonical', () {
    final source = File(
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ).readAsStringSync();

    expect(source, contains('const HealthPlusView()'));
    expect(source, contains('const GiftModeView()'));
    expect(source, contains('const SenderBookingCanvas()'));
    expect(source, contains('onOpenActivity: () => _selectTab(2)'));
    expect(source, contains('onOpenWallet: () => _selectTab(3)'));
  });

  test('authenticated Sender sessions restore before showing Sign In', () {
    final homeSource = File(
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ).readAsStringSync();
    final webSource = File('lib/web_sender_app.dart').readAsStringSync();

    expect(homeSource, contains('_authRestoring'));
    expect(homeSource, contains('_SenderAuthRestoringSplash'));
    expect(homeSource, contains('Restoring your session'));
    expect(homeSource, contains('authStateChanges().listen'));
    expect(homeSource, contains('Persistence.LOCAL'));
    expect(homeSource, contains('_entry = user == null'));
    expect(homeSource, contains('_SenderEntryScreen.app'));
    expect(homeSource, isNot(contains('Persistence.SESSION')));
    expect(webSource, contains("query['tab'] = tab"));
    expect(webSource, contains("query.remove('tab')"));
    expect(webSource, contains("'send' || 'booking' || 'book'"));
    expect(webSource, contains('initialIndex: _senderMobileIndexForEntry'));
    expect(webSource, contains('onTabChanged: _replaceSenderMobileTabRoute'));
  });

  test('logout remains the explicit Sender session clearing action', () {
    final profileSource = File(
      'lib/app/sender_mobile/sender_mobile_profile.dart',
    ).readAsStringSync();
    final homeSource = File(
      'lib/app/sender_mobile/sender_mobile_home.dart',
    ).readAsStringSync();

    expect(profileSource, contains('Future<void> logout() => auth.signOut()'));
    expect(homeSource, contains('onLoggedOut: () => setState'));
    expect(homeSource, isNot(contains('clearPersistence')));
  });
}
