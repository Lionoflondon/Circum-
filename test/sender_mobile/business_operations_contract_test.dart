import 'package:flutter_test/flutter_test.dart';
import 'package:circum/app/business/business_models.dart';

void main() {
  test('Business operations summary preserves server-owned aggregate values', () {
    final summary = BusinessOperationsSummary.fromMap({
      'deliveryCount': 250,
      'completedCount': 230,
      'failedOrCancelledCount': 5,
      'activeCount': 15,
      'monthlyDeliveries': 42,
      'monthlySpend': 1234.56,
      'averageDeliveryMinutes': 37,
      'serviceMix': {'standard': 100, 'express': 80, 'economy': 70},
    });
    expect(summary.deliveryCount, 250);
    expect(summary.monthlySpend, 1234.56);
    expect(summary.averageDeliveryMinutes, 37);
    expect(summary.serviceMix['express'], 80);
  });

  test('Business delivery uses redacted projection and watchdog SLA state', () {
    final delivery = BusinessDelivery.fromMap('delivery-1', {
      'pickup': 'The Shard, London SE1 9SG',
      'dropoff': 'Battersea Power Station, London SW11 8AL',
      'status': 'collected',
      'amount': 21.35,
      'createdAtMillis': 1786316400000,
      'slaStatus': 'RED',
      'incidentType': 'collected_no_movement',
    });
    expect(delivery.pickup, contains('SE1 9SG'));
    expect(delivery.amount, 21.35);
    expect(delivery.slaStatus, 'RED');
    expect(delivery.incidentType, 'collected_no_movement');
  });

  test('Business permissions keep finance separate from operations', () {
    final operations = BusinessWorkspacePermissions.fromMap({
      'deliveries': true,
      'reports': true,
      'finance': false,
    });
    expect(operations.deliveries, isTrue);
    expect(operations.reports, isTrue);
    expect(operations.finance, isFalse);
  });

  test('Business delivery pagination suppresses duplicate cursor retries', () {
    final delivery = BusinessDelivery.fromMap('delivery-1', {
      'status': 'requested',
      'createdAtMillis': 1786316400000,
    });
    final workspace = BusinessWorkspaceData(
      account: BusinessAccount.fromMap('business-1', {'businessName': 'Acme'}),
      deliveries: [delivery],
      invoices: const [],
      healthRequests: const [],
      giftRequests: const [],
      wallet: BusinessWalletSummary.empty,
    );
    final merged = workspace.withDeliveryPage(BusinessDeliveryPage(
      deliveries: [delivery],
      nextCursor: null,
    ));
    expect(merged.deliveries, hasLength(1));
  });
}

