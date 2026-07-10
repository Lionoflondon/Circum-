import 'package:circum/design_inventory/design_inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonical design inventory', () {
    test('registers locked screens and states', () {
      expect(screenRegistry.length, 55);
      expect(stateRegistry.length, 24);

      expect(screenById('SEN-001')?.name, 'Home');
      expect(screenById('SEN-014')?.name, 'Wallet');
      expect(screenById('RID-006')?.name, 'Earnings');
      expect(screenById('HLT-010')?.name, 'Confirmation');
      expect(screenById('GIF-011')?.name, 'Gift Story');
      expect(screenById('FIN-012')?.name, 'Admin Finance');

      expect(stateById('SEN-012-ST-01')?.name, 'Looking for Rider');
      expect(stateById('SEN-012-ST-10')?.name, 'Delivered');
      expect(stateById('HLT-001-ST-07')?.name, 'Delivered');
      expect(stateById('FIN-001-ST-06')?.name, 'Offers');
    });

    test('uses only locked status values and product prefixes', () {
      expect(
        DesignInventoryStatus.values.map((status) => status.label),
        [
          'DESIGNED',
          'IN_PROGRESS',
          'IMPLEMENTED',
          'DEPLOYED',
          'BACKEND_ONLY',
          'UI_PENDING',
          'REDESIGN_REQUIRED',
          'DEPRECATED',
        ],
      );
      expect(DesignInventoryProduct.sender.prefix, 'SEN');
      expect(DesignInventoryProduct.rider.prefix, 'RID');
      expect(DesignInventoryProduct.health.prefix, 'HLT');
      expect(DesignInventoryProduct.gifts.prefix, 'GIF');
      expect(DesignInventoryProduct.finance.prefix, 'FIN');
      expect(DesignInventoryProduct.business.prefix, 'BUS');
      expect(DesignInventoryProduct.admin.prefix, 'ADM');
      expect(DesignInventoryProduct.iris.prefix, 'IRS');
      expect(DesignInventoryProduct.vanguard.prefix, 'VAN');
      expect(DesignInventoryProduct.authentication.prefix, 'AUT');
      expect(DesignInventoryProduct.notifications.prefix, 'NOT');
    });

    test('query helpers return product and status slices', () {
      expect(querySender().screens.map((screen) => screen.id),
          contains('SEN-012'));
      expect(
          queryRider().screens.map((screen) => screen.id), contains('RID-001'));
      expect(queryHealth().screens.map((screen) => screen.id),
          contains('HLT-001'));
      expect(
          queryGifts().screens.map((screen) => screen.id), contains('GIF-001'));
      expect(queryFinance().screens.map((screen) => screen.id),
          contains('FIN-001'));
      expect(queryBusiness().screens, isEmpty);
      expect(queryAdmin().screens, isEmpty);

      expect(queryImplemented().screens, isNotEmpty);
      expect(queryDeployed().screens, isNotEmpty);
      expect(queryLive().screens.length, queryDeployed().screens.length);
    });

    test('missing report identifies unfinished inventory work', () {
      final report = buildInventoryMissingReport();
      final summary = buildInventorySummary();

      expect(report.hasMissingWork, isTrue);
      expect(
        report.missingScreens.map((screen) => screen.id),
        containsAll(['RID-006', 'GIF-011', 'FIN-006', 'FIN-010']),
      );
      expect(report.missingStates, isEmpty);
      expect(summary['screens'], 55);
      expect(summary['states'], 24);
      expect(summary['missingStates'], isEmpty);
      expect(summary['missingDeployment'], isNotEmpty);
    });

    test('screen state references resolve to registered states', () {
      for (final screen in screenRegistry) {
        for (final stateId in screen.stateIds) {
          expect(
            stateById(stateId),
            isNotNull,
            reason: '${screen.id} references unknown state $stateId',
          );
        }
      }
    });
  });
}
