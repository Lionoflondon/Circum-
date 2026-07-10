import 'design_status.dart';
import 'screen_registry.dart';
import 'state_registry.dart';

class DesignInventoryResult {
  final List<DesignScreenRecord> screens;
  final List<DesignStateRecord> states;

  const DesignInventoryResult({
    required this.screens,
    required this.states,
  });

  List<DesignScreenRecord> get missingScreens =>
      screens.where((screen) => screen.isMissingWork).toList(growable: false);

  List<DesignStateRecord> get missingStates =>
      states.where((state) => state.isMissingWork).toList(growable: false);
}

DesignInventoryResult queryProduct(DesignInventoryProduct product) {
  final screens = screenRegistry
      .where((screen) => screen.product == product)
      .toList(growable: false);
  final screenIds = screens.map((screen) => screen.id).toSet();
  final states = stateRegistry
      .where((state) => screenIds.contains(state.screenId))
      .toList(growable: false);
  return DesignInventoryResult(screens: screens, states: states);
}

DesignInventoryResult querySender() =>
    queryProduct(DesignInventoryProduct.sender);

DesignInventoryResult queryRider() =>
    queryProduct(DesignInventoryProduct.rider);

DesignInventoryResult queryHealth() =>
    queryProduct(DesignInventoryProduct.health);

DesignInventoryResult queryGifts() =>
    queryProduct(DesignInventoryProduct.gifts);

DesignInventoryResult queryFinance() =>
    queryProduct(DesignInventoryProduct.finance);

DesignInventoryResult queryBusiness() =>
    queryProduct(DesignInventoryProduct.business);

DesignInventoryResult queryAdmin() =>
    queryProduct(DesignInventoryProduct.admin);

DesignInventoryResult queryMissing() {
  return DesignInventoryResult(
    screens: screenRegistry
        .where((screen) => screen.isMissingWork)
        .toList(growable: false),
    states: stateRegistry
        .where((state) => state.isMissingWork)
        .toList(growable: false),
  );
}

DesignInventoryResult queryDesigned() =>
    _queryStatus(DesignInventoryStatus.designed);

DesignInventoryResult queryImplemented() =>
    _queryStatus(DesignInventoryStatus.implemented);

DesignInventoryResult queryDeployed() =>
    _queryStatus(DesignInventoryStatus.deployed);

DesignInventoryResult queryLive() => queryDeployed();

DesignInventoryResult _queryStatus(DesignInventoryStatus status) {
  return DesignInventoryResult(
    screens: screenRegistry
        .where((screen) => screen.status == status)
        .toList(growable: false),
    states: stateRegistry
        .where((state) => state.status == status)
        .toList(growable: false),
  );
}

DesignScreenRecord? screenById(String id) {
  for (final screen in screenRegistry) {
    if (screen.id == id) return screen;
  }
  return null;
}

DesignStateRecord? stateById(String id) {
  for (final state in stateRegistry) {
    if (state.id == id) return state;
  }
  return null;
}
