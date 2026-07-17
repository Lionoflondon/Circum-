import 'dart:math';

const vanguardHighValueThresholdGbp = 250.0;
const vanguardMaxPinAttemptsBeforeReview = 5;
const vanguardProtocolVersion = 'vanguard_protocol_v1';

enum VanguardProtocolStatus {
  notRequired,
  optional,
  required,
  pickupVerificationPending,
  pickupVerified,
  secureCustody,
  handoverPending,
  handoverVerified,
  completed,
  issueReported,
}

enum VanguardProtocolStage {
  pickup,
  custody,
  handover,
}

class VanguardProtectedCategory {
  final String name;
  final List<String> keywords;

  const VanguardProtectedCategory({
    required this.name,
    required this.keywords,
  });
}

const vanguardProtectedCategoryRegistry = [
  VanguardProtectedCategory(
    name: 'Consumer Electronics',
    keywords: [
      'iphone',
      'android phone',
      'android phones',
      'smartphone',
      'smartphones',
      'satellite phone',
      'satellite phones',
      'tablet',
      'tablets',
      'ipad',
      'ipads',
      'laptop',
      'laptops',
      'macbook',
      'macbooks',
      'desktop computer',
      'desktop computers',
      'gaming pc',
      'gaming pcs',
      'computer component',
      'computer components',
      'graphics card',
      'graphics cards',
      'gpu',
      'monitor',
      'monitors',
      'smartwatch',
      'smartwatches',
      'apple watch',
      'samsung watch',
      'fitness tracker',
      'fitness trackers',
      'camera',
      'cameras',
      'dslr',
      'dslr camera',
      'mirrorless camera',
      'camera lens',
      'camera lenses',
      'drone',
      'drones',
      'projector',
      'projectors',
      'vr headset',
      'vr headsets',
      'gaming console',
      'gaming consoles',
      'playstation',
      'ps5',
      'xbox',
      'nintendo switch',
      'steam deck',
      'high-end headphones',
      'headphones',
      'audio equipment',
      'dj equipment',
    ],
  ),
  VanguardProtectedCategory(
    name: 'Luxury Goods',
    keywords: [
      'designer handbag',
      'designer handbags',
      'designer bag',
      'designer shoes',
      'designer clothing',
      'luxury watch',
      'luxury watches',
      'collectible watch',
      'collectible watches',
      'rolex',
      'sunglasses',
      'limited edition fashion',
      'limited edition fashion item',
    ],
  ),
  VanguardProtectedCategory(
    name: 'Jewellery and Precious Items',
    keywords: [
      'jewellery',
      'jewelry',
      'ring',
      'rings',
      'engagement ring',
      'wedding ring',
      'necklace',
      'necklaces',
      'bracelet',
      'bracelets',
      'earring',
      'earrings',
      'gold item',
      'gold items',
      'silver item',
      'silver items',
      'platinum item',
      'platinum items',
      'diamond',
      'diamonds',
      'gemstone',
      'gemstones',
      'precious metal',
      'precious metals',
    ],
  ),
  VanguardProtectedCategory(
    name: 'Collectibles',
    keywords: [
      'trading card',
      'trading cards',
      'pokemon card',
      'pokemon cards',
      'pokémon card',
      'pokémon cards',
      'sports card',
      'sports cards',
      'rare collectible',
      'rare collectibles',
      'signed memorabilia',
      'limited edition merchandise',
      'coin',
      'coins',
      'rare banknote',
      'rare banknotes',
      'stamp',
      'stamps',
      'antique',
      'antiques',
    ],
  ),
  VanguardProtectedCategory(
    name: 'Music and Creative Equipment',
    keywords: [
      'guitar',
      'guitars',
      'violin',
      'violins',
      'cello',
      'cellos',
      'saxophone',
      'saxophones',
      'trumpet',
      'trumpets',
      'musical instrument',
      'musical instruments',
      'studio microphone',
      'studio microphones',
      'recording equipment',
      'professional audio gear',
    ],
  ),
  VanguardProtectedCategory(
    name: 'Professional Equipment',
    keywords: [
      'surveying equipment',
      'medical device',
      'medical devices',
      'scientific equipment',
      'testing equipment',
      'professional camera',
      'professional cameras',
      'commercial drone',
      'commercial drones',
    ],
  ),
  VanguardProtectedCategory(
    name: 'Business Assets',
    keywords: [
      'company laptop',
      'company laptops',
      'workstation',
      'workstations',
      'business electronics',
      'secure document',
      'secure documents',
      'legal document',
      'legal documents',
      'tender document',
      'tender documents',
      'contract',
      'contracts',
      'confidential business material',
      'confidential business materials',
      'confidential business document',
      'confidential business documents',
      'confidential documents',
    ],
  ),
  VanguardProtectedCategory(
    name: 'Luxury and High-End Lifestyle',
    keywords: [
      'perfume collection',
      'perfume collections',
      'rare wine',
      'rare wines',
      'luxury spirit',
      'luxury spirits',
      'art piece',
      'art pieces',
      'painting',
      'paintings',
      'sculpture',
      'sculptures',
      'limited edition artwork',
    ],
  ),
  VanguardProtectedCategory(
    name: 'Vehicle Related',
    keywords: [
      'alloy wheel',
      'alloy wheels',
      'performance car part',
      'performance car parts',
      'vehicle ecu',
      'vehicle ecus',
      'motorcycle part',
      'motorcycle parts',
      'high-value vehicle component',
      'high-value vehicle components',
    ],
  ),
  VanguardProtectedCategory(
    name: 'Sports and Hobby Equipment',
    keywords: [
      'racing bicycle',
      'racing bicycles',
      'e-bike',
      'e-bikes',
      'ebike',
      'ebikes',
      'professional golf club',
      'professional golf clubs',
      'professional photography equipment',
      'competitive gaming equipment',
    ],
  ),
];

class VanguardPins {
  final String collectionPin;
  final String deliveryPin;

  const VanguardPins({
    required this.collectionPin,
    required this.deliveryPin,
  });
}

class VanguardPinCheck {
  final bool passed;
  final int attemptCount;
  final bool flagForReview;
  final String errorMessage;

  const VanguardPinCheck({
    required this.passed,
    required this.attemptCount,
    required this.flagForReview,
    required this.errorMessage,
  });
}

class VanguardProtocolDecision {
  final bool enabled;
  final bool required;
  final String requiredReason;
  final VanguardProtocolStatus status;

  const VanguardProtocolDecision({
    required this.enabled,
    required this.required,
    required this.requiredReason,
    required this.status,
  });
}

class VanguardProtection {
  static const senderActiveLabel = '🛡 Vanguard Protection Active';
  static const protocolTimeline = [
    'Vanguard pickup verification',
    'Secure custody',
    'Secure transit',
    'Secure handover',
  ];
  static const pickupChecklist = [
    'Verify parcel',
    'Verify packaging',
    'Required evidence',
    'Rider declaration',
  ];
  static const handoverChecklist = [
    'Recipient verification if policy requires',
    'Delivery evidence',
    'Secure handover declaration',
  ];

  static bool shouldEnable({
    required String description,
    String? packageType,
    double? declaredValueGbp,
    bool manuallySelected = false,
  }) {
    if (manuallySelected) return true;
    if (declaredValueGbp != null &&
        declaredValueGbp > vanguardHighValueThresholdGbp) {
      return true;
    }
    return matchedCategoryName(
          description: description,
          packageType: packageType,
        ) !=
        null;
  }

  static VanguardProtocolDecision decideProtocol({
    required String description,
    String? packageType,
    double? declaredValueGbp,
    bool manuallySelected = false,
    bool irisRequired = false,
    String? irisRequiredReason,
  }) {
    final matchedCategory = matchedCategoryName(
      description: description,
      packageType: packageType,
    );
    final required = irisRequired ||
        matchedCategory != null ||
        (declaredValueGbp != null &&
            declaredValueGbp > vanguardHighValueThresholdGbp);
    final enabled = manuallySelected || required;
    return VanguardProtocolDecision(
      enabled: enabled,
      required: required,
      requiredReason: !required
          ? ''
          : irisRequiredReason?.trim().isNotEmpty == true
              ? irisRequiredReason!.trim()
              : matchedCategory != null
                  ? 'IRIS policy requires Vanguard for $matchedCategory.'
                  : 'Declared value requires Vanguard protocol.',
      status: enabled
          ? VanguardProtocolStatus.pickupVerificationPending
          : VanguardProtocolStatus.notRequired,
    );
  }

  static bool isProtocolEnabled(Map<String, dynamic> delivery) {
    final protocol =
        (delivery['vanguardProtocol'] as Map?)?.cast<String, dynamic>();
    return delivery['vanguardProtocolEnabled'] == true ||
        delivery['vanguardEnabled'] == true ||
        protocol?['enabled'] == true ||
        ((delivery['vanguardProtection'] as Map?)?['enabled'] == true);
  }

  static VanguardProtocolStatus statusFromDelivery(
    Map<String, dynamic> delivery,
  ) {
    final raw = '${delivery['vanguardStatus'] ?? ''}'.trim();
    if (raw.isNotEmpty) return statusFromWire(raw);
    if (!isProtocolEnabled(delivery)) return VanguardProtocolStatus.notRequired;
    if (delivery['deliveryPinVerified'] == true) {
      return VanguardProtocolStatus.completed;
    }
    if (delivery['collectionPinVerified'] == true) {
      return VanguardProtocolStatus.secureCustody;
    }
    return VanguardProtocolStatus.pickupVerificationPending;
  }

  static VanguardProtocolStatus statusFromWire(String value) {
    final normalized =
        value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return switch (normalized) {
      'optional' => VanguardProtocolStatus.optional,
      'required' => VanguardProtocolStatus.required,
      'pickup_verification_pending' =>
        VanguardProtocolStatus.pickupVerificationPending,
      'pickup_verified' => VanguardProtocolStatus.pickupVerified,
      'secure_custody' => VanguardProtocolStatus.secureCustody,
      'handover_pending' => VanguardProtocolStatus.handoverPending,
      'handover_verified' => VanguardProtocolStatus.handoverVerified,
      'completed' => VanguardProtocolStatus.completed,
      'issue_reported' => VanguardProtocolStatus.issueReported,
      _ => VanguardProtocolStatus.notRequired,
    };
  }

  static String statusWire(VanguardProtocolStatus status) {
    return switch (status) {
      VanguardProtocolStatus.notRequired => 'not_required',
      VanguardProtocolStatus.optional => 'optional',
      VanguardProtocolStatus.required => 'required',
      VanguardProtocolStatus.pickupVerificationPending =>
        'pickup_verification_pending',
      VanguardProtocolStatus.pickupVerified => 'pickup_verified',
      VanguardProtocolStatus.secureCustody => 'secure_custody',
      VanguardProtocolStatus.handoverPending => 'handover_pending',
      VanguardProtocolStatus.handoverVerified => 'handover_verified',
      VanguardProtocolStatus.completed => 'completed',
      VanguardProtocolStatus.issueReported => 'issue_reported',
    };
  }

  static String statusLabel(VanguardProtocolStatus status) {
    return switch (status) {
      VanguardProtocolStatus.notRequired => 'Not required',
      VanguardProtocolStatus.optional => 'Optional',
      VanguardProtocolStatus.required => 'Required',
      VanguardProtocolStatus.pickupVerificationPending =>
        'Vanguard pickup verification',
      VanguardProtocolStatus.pickupVerified => 'Pickup verified',
      VanguardProtocolStatus.secureCustody => 'Secure custody active',
      VanguardProtocolStatus.handoverPending => 'Secure handover pending',
      VanguardProtocolStatus.handoverVerified => 'Handover verified',
      VanguardProtocolStatus.completed => 'Protocol completed',
      VanguardProtocolStatus.issueReported => 'Issue reported',
    };
  }

  static bool canCompletePickup(Map<String, dynamic> delivery) {
    if (!isProtocolEnabled(delivery)) return true;
    final status = statusFromDelivery(delivery);
    return status == VanguardProtocolStatus.pickupVerified ||
        status == VanguardProtocolStatus.secureCustody ||
        status == VanguardProtocolStatus.handoverPending ||
        status == VanguardProtocolStatus.handoverVerified ||
        status == VanguardProtocolStatus.completed;
  }

  static bool canCompleteDropoff(Map<String, dynamic> delivery) {
    if (!isProtocolEnabled(delivery)) return true;
    final status = statusFromDelivery(delivery);
    return status == VanguardProtocolStatus.handoverVerified ||
        status == VanguardProtocolStatus.completed;
  }

  static Map<String, dynamic> receiptSummary(
    Map<String, dynamic> delivery, {
    double fee = 1.99,
  }) {
    if (!isProtocolEnabled(delivery)) return const {};
    final status = statusFromDelivery(delivery);
    return {
      'label': 'Vanguard Protection',
      'protocolCompleted': status == VanguardProtocolStatus.completed,
      'verificationCompleted': delivery['collectionPinVerified'] == true &&
          delivery['deliveryPinVerified'] == true,
      'fee': fee,
      'issue': status == VanguardProtocolStatus.issueReported
          ? delivery['vanguardIssueReason'] ?? 'Issue reported'
          : null,
    };
  }

  static VanguardPins generatePins({Random? random}) {
    final rng = random ?? Random.secure();
    final collectionPin = _sixDigitPin(rng);
    var deliveryPin = _sixDigitPin(rng);
    while (deliveryPin == collectionPin) {
      deliveryPin = _sixDigitPin(rng);
    }
    return VanguardPins(
      collectionPin: collectionPin,
      deliveryPin: deliveryPin,
    );
  }

  static Map<String, dynamic> initialFields({
    required String description,
    String? packageType,
    double? declaredValueGbp,
    bool manuallySelected = false,
    bool irisRequired = false,
    String? irisRequiredReason,
    Random? random,
  }) {
    final matchedCategory = matchedCategoryName(
      description: description,
      packageType: packageType,
    );
    final decision = decideProtocol(
      description: description,
      packageType: packageType,
      declaredValueGbp: declaredValueGbp,
      manuallySelected: manuallySelected,
      irisRequired: irisRequired,
      irisRequiredReason: irisRequiredReason,
    );
    final enabled = decision.enabled;
    if (!enabled) {
      return const {
        'vanguardEnabled': false,
        'vanguardProtocolEnabled': false,
        'vanguardStatus': 'not_required',
      };
    }
    final pins = generatePins(random: random);
    final trigger = _trigger(
      declaredValueGbp: declaredValueGbp,
      manuallySelected: manuallySelected,
      matchedCategory: matchedCategory,
      irisRequired: irisRequired,
    );
    return {
      'vanguardEnabled': true,
      'vanguardProtocolEnabled': true,
      'vanguardRequiredReason': decision.requiredReason,
      'vanguardStatus': statusWire(decision.status),
      'vanguardVerificationState': {
        'pickup': 'pending',
        'custody': 'pending',
        'handover': 'pending',
      },
      'vanguardAuditTrail': [
        {
          'event': 'vanguard_protocol_enabled',
          'status': statusWire(decision.status),
          'trigger': trigger,
          'reason': decision.requiredReason,
        },
      ],
      'vanguardEvidence': {
        'pickup': [],
        'handover': [],
      },
      'vanguardProtocol': {
        'enabled': true,
        'required': decision.required,
        'version': vanguardProtocolVersion,
        'status': statusWire(decision.status),
        'reason': decision.requiredReason,
        'timeline': protocolTimeline,
      },
      'vanguardProtection': {
        'enabled': true,
        'highValueThresholdGbp': vanguardHighValueThresholdGbp,
        'trigger': trigger,
        'matchedCategory': matchedCategory,
        'registryVersion': 1,
        // TODO: Hash these values server-side when a backend PIN hashing helper
        // is available. Keeping them isolated avoids spreading raw PIN fields.
        'collectionPin': pins.collectionPin,
        'deliveryPin': pins.deliveryPin,
      },
      'collectionPinVerified': false,
      'collectionPinVerifiedAt': null,
      'collectionPinVerifiedBy': null,
      'deliveryPinVerified': false,
      'deliveryPinVerifiedAt': null,
      'deliveryPinVerifiedBy': null,
      'collectionPinAttemptCount': 0,
      'deliveryPinAttemptCount': 0,
      'vanguardReviewRequired': false,
    };
  }

  static String? matchedCategoryName({
    required String description,
    String? packageType,
  }) {
    final text = _normalized('$description ${packageType ?? ''}');
    for (final category in vanguardProtectedCategoryRegistry) {
      for (final keyword in category.keywords) {
        if (text.contains(_normalized(keyword))) return category.name;
      }
    }
    return null;
  }

  static VanguardPinCheck verifyPin({
    required bool enabled,
    required String? expectedPin,
    required String enteredPin,
    required int attemptCount,
    required String stage,
  }) {
    if (!enabled) {
      return const VanguardPinCheck(
        passed: true,
        attemptCount: 0,
        flagForReview: false,
        errorMessage: '',
      );
    }
    final nextAttemptCount = attemptCount + 1;
    final normalizedExpected = (expectedPin ?? '').trim();
    final normalizedEntered = enteredPin.trim();
    final passed = normalizedExpected.length == 6 &&
        normalizedEntered.length == 6 &&
        normalizedEntered == normalizedExpected;
    final flagForReview =
        !passed && nextAttemptCount >= vanguardMaxPinAttemptsBeforeReview;
    final label = stage == 'delivery' ? 'delivery' : 'collection';
    return VanguardPinCheck(
      passed: passed,
      attemptCount: nextAttemptCount,
      flagForReview: flagForReview,
      errorMessage: passed
          ? ''
          : 'Incorrect $label PIN. Ask the ${stage == 'delivery' ? 'recipient' : 'sender'} to confirm the code.',
    );
  }

  static String? collectionPin(Map<String, dynamic> delivery) {
    final protection =
        (delivery['vanguardProtection'] as Map?)?.cast<String, dynamic>();
    return '${protection?['collectionPin'] ?? ''}'.trim();
  }

  static String? deliveryPin(Map<String, dynamic> delivery) {
    final protection =
        (delivery['vanguardProtection'] as Map?)?.cast<String, dynamic>();
    return '${protection?['deliveryPin'] ?? ''}'.trim();
  }

  static String _sixDigitPin(Random random) {
    return (100000 + random.nextInt(900000)).toString();
  }

  static String _trigger({
    required double? declaredValueGbp,
    required bool manuallySelected,
    required String? matchedCategory,
    required bool irisRequired,
  }) {
    if (irisRequired) return 'iris_policy_required';
    if (manuallySelected) return 'manual_user_selection';
    if (declaredValueGbp != null &&
        declaredValueGbp > vanguardHighValueThresholdGbp) {
      return 'declared_value';
    }
    if (matchedCategory != null) return 'protected_category';
    return 'unknown';
  }

  static String _normalized(String value) {
    return value
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
