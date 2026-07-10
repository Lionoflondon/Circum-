import 'design_status.dart';

const liveTrackingStateRegistry = <DesignStateRecord>[
  DesignStateRecord(
    id: 'SEN-012-ST-01',
    name: 'Looking for Rider',
    screenId: 'SEN-012',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'SEN-012-ST-02',
    name: 'Rider Accepted',
    screenId: 'SEN-012',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'SEN-012-ST-03',
    name: 'Heading to Pickup',
    screenId: 'SEN-012',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'SEN-012-ST-04',
    name: 'Arrived',
    screenId: 'SEN-012',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'SEN-012-ST-05',
    name: 'Waiting',
    screenId: 'SEN-012',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'SEN-012-ST-06',
    name: 'Pickup Verification',
    screenId: 'SEN-012',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'SEN-012-ST-07',
    name: 'Collected',
    screenId: 'SEN-012',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'SEN-012-ST-08',
    name: 'In Transit',
    screenId: 'SEN-012',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'SEN-012-ST-09',
    name: 'Nearby',
    screenId: 'SEN-012',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'SEN-012-ST-10',
    name: 'Delivered',
    screenId: 'SEN-012',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'SEN-012-ST-11',
    name: 'Delivery Update',
    screenId: 'SEN-012',
    status: DesignInventoryStatus.deployed,
  ),
];

const healthStateRegistry = <DesignStateRecord>[
  DesignStateRecord(
    id: 'HLT-001-ST-01',
    name: 'No Active Pickup',
    screenId: 'HLT-001',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'HLT-001-ST-02',
    name: 'Upcoming Pickup',
    screenId: 'HLT-001',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'HLT-001-ST-03',
    name: 'Prescription Ready',
    screenId: 'HLT-001',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'HLT-001-ST-04',
    name: 'Rider Assigned',
    screenId: 'HLT-001',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'HLT-001-ST-05',
    name: 'Collected',
    screenId: 'HLT-001',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'HLT-001-ST-06',
    name: 'On The Way',
    screenId: 'HLT-001',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'HLT-001-ST-07',
    name: 'Delivered',
    screenId: 'HLT-001',
    status: DesignInventoryStatus.deployed,
  ),
];

const financeStateRegistry = <DesignStateRecord>[
  DesignStateRecord(
    id: 'FIN-001-ST-01',
    name: 'Empty Wallet',
    screenId: 'FIN-001',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'FIN-001-ST-02',
    name: 'Available Roth',
    screenId: 'FIN-001',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'FIN-001-ST-03',
    name: 'Payment Methods',
    screenId: 'FIN-001',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'FIN-001-ST-04',
    name: 'Recent Activity',
    screenId: 'FIN-001',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'FIN-001-ST-05',
    name: 'Referral Rewards',
    screenId: 'FIN-001',
    status: DesignInventoryStatus.deployed,
  ),
  DesignStateRecord(
    id: 'FIN-001-ST-06',
    name: 'Offers',
    screenId: 'FIN-001',
    status: DesignInventoryStatus.deployed,
  ),
];

const stateRegistry = <DesignStateRecord>[
  ...liveTrackingStateRegistry,
  ...healthStateRegistry,
  ...financeStateRegistry,
];
