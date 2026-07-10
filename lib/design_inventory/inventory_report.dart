import 'design_registry.dart';
import 'design_status.dart';
import 'screen_registry.dart';
import 'state_registry.dart';

class DesignInventoryMissingReport {
  final List<DesignScreenRecord> missingScreens;
  final List<DesignStateRecord> missingStates;
  final List<DesignScreenRecord> missingUi;
  final List<DesignScreenRecord> missingBackend;
  final List<DesignScreenRecord> missingTests;
  final List<DesignScreenRecord> missingDeployment;
  final List<DesignScreenRecord> missingDocumentation;

  const DesignInventoryMissingReport({
    required this.missingScreens,
    required this.missingStates,
    required this.missingUi,
    required this.missingBackend,
    required this.missingTests,
    required this.missingDeployment,
    required this.missingDocumentation,
  });

  bool get hasMissingWork =>
      missingScreens.isNotEmpty ||
      missingStates.isNotEmpty ||
      missingUi.isNotEmpty ||
      missingBackend.isNotEmpty ||
      missingTests.isNotEmpty ||
      missingDeployment.isNotEmpty ||
      missingDocumentation.isNotEmpty;
}

DesignInventoryMissingReport buildInventoryMissingReport() {
  return DesignInventoryMissingReport(
    missingScreens: queryMissing().screens,
    missingStates: queryMissing().states,
    missingUi: screenRegistry
        .where((screen) =>
            screen.ui == DesignInventoryStatus.uiPending ||
            screen.status == DesignInventoryStatus.uiPending ||
            screen.status == DesignInventoryStatus.redesignRequired)
        .toList(growable: false),
    missingBackend: screenRegistry
        .where((screen) => screen.backend == DesignInventoryStatus.uiPending)
        .toList(growable: false),
    missingTests: screenRegistry
        .where((screen) => screen.missingWork.any(
              (item) => item.toLowerCase().contains('test'),
            ))
        .toList(growable: false),
    missingDeployment: screenRegistry
        .where((screen) => screen.deployment != DesignInventoryStatus.deployed)
        .toList(growable: false),
    missingDocumentation: screenRegistry
        .where((screen) => screen.missingWork.any(
              (item) => item.toLowerCase().contains('documentation'),
            ))
        .toList(growable: false),
  );
}

Map<String, Object> buildInventorySummary() {
  final missing = buildInventoryMissingReport();
  return {
    'screens': screenRegistry.length,
    'states': stateRegistry.length,
    'missingScreens':
        missing.missingScreens.map((screen) => screen.id).toList(),
    'missingStates': missing.missingStates.map((state) => state.id).toList(),
    'missingUi': missing.missingUi.map((screen) => screen.id).toList(),
    'missingBackend':
        missing.missingBackend.map((screen) => screen.id).toList(),
    'missingTests': missing.missingTests.map((screen) => screen.id).toList(),
    'missingDeployment':
        missing.missingDeployment.map((screen) => screen.id).toList(),
    'missingDocumentation':
        missing.missingDocumentation.map((screen) => screen.id).toList(),
  };
}
