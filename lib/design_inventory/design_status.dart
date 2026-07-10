enum DesignInventoryStatus {
  designed('DESIGNED'),
  inProgress('IN_PROGRESS'),
  implemented('IMPLEMENTED'),
  deployed('DEPLOYED'),
  backendOnly('BACKEND_ONLY'),
  uiPending('UI_PENDING'),
  redesignRequired('REDESIGN_REQUIRED'),
  deprecated('DEPRECATED');

  final String label;

  const DesignInventoryStatus(this.label);
}

enum DesignInventoryProduct {
  sender('SEN', 'Sender'),
  rider('RID', 'Rider'),
  health('HLT', 'Health+'),
  gifts('GIF', 'Gifts'),
  finance('FIN', 'Finance'),
  business('BUS', 'Business'),
  admin('ADM', 'Admin'),
  iris('IRS', 'IRIS'),
  vanguard('VAN', 'Vanguard'),
  authentication('AUT', 'Authentication'),
  notifications('NOT', 'Notifications');

  final String prefix;
  final String label;

  const DesignInventoryProduct(this.prefix, this.label);
}

class DesignScreenRecord {
  final String id;
  final String name;
  final DesignInventoryProduct product;
  final DesignInventoryStatus status;
  final List<String> stateIds;
  final DesignInventoryStatus backend;
  final DesignInventoryStatus ui;
  final DesignInventoryStatus deployment;
  final String owner;
  final List<String> missingWork;

  const DesignScreenRecord({
    required this.id,
    required this.name,
    required this.product,
    required this.status,
    this.stateIds = const [],
    required this.backend,
    required this.ui,
    required this.deployment,
    this.owner = 'Jason Adesanya',
    this.missingWork = const [],
  });

  bool get isLive => deployment == DesignInventoryStatus.deployed;

  bool get isMissingWork =>
      missingWork.isNotEmpty ||
      status == DesignInventoryStatus.uiPending ||
      status == DesignInventoryStatus.backendOnly ||
      status == DesignInventoryStatus.redesignRequired ||
      status == DesignInventoryStatus.inProgress ||
      backend == DesignInventoryStatus.uiPending ||
      ui == DesignInventoryStatus.uiPending ||
      deployment != DesignInventoryStatus.deployed;
}

class DesignStateRecord {
  final String id;
  final String name;
  final String screenId;
  final DesignInventoryStatus status;
  final String owner;
  final List<String> missingWork;

  const DesignStateRecord({
    required this.id,
    required this.name,
    required this.screenId,
    required this.status,
    this.owner = 'Jason Adesanya',
    this.missingWork = const [],
  });

  bool get isMissingWork =>
      missingWork.isNotEmpty ||
      status == DesignInventoryStatus.uiPending ||
      status == DesignInventoryStatus.backendOnly ||
      status == DesignInventoryStatus.redesignRequired ||
      status == DesignInventoryStatus.inProgress;
}
