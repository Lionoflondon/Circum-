import 'dart:math';

const vanguardHighValueThresholdGbp = 250.0;
const vanguardMaxPinAttemptsBeforeReview = 5;

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

class VanguardProtection {
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
    Random? random,
  }) {
    final matchedCategory = matchedCategoryName(
      description: description,
      packageType: packageType,
    );
    final enabled = shouldEnable(
      description: description,
      packageType: packageType,
      declaredValueGbp: declaredValueGbp,
      manuallySelected: manuallySelected,
    );
    if (!enabled) {
      return const {
        'vanguardEnabled': false,
      };
    }
    return {
      'vanguardEnabled': true,
      'vanguardProtection': {
        'enabled': true,
        'highValueThresholdGbp': vanguardHighValueThresholdGbp,
        'trigger': _trigger(
          declaredValueGbp: declaredValueGbp,
          manuallySelected: manuallySelected,
          matchedCategory: matchedCategory,
        ),
        'matchedCategory': matchedCategory,
        'registryVersion': 1,
      },
      'collectionPinVerified': false,
      'collectionPinVerifiedAt': null,
      'collectionPinVerifiedBy': null,
      'deliveryPinVerified': false,
      'deliveryPinVerifiedAt': null,
      'deliveryPinVerifiedBy': null,
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
          : 'Incorrect $label PIN. Ask the ${stage == 'delivery' ? 'recipient' : 'collection contact'} to confirm the code.',
    );
  }

  static String? collectionPin(Map<String, dynamic> delivery) {
    return null;
  }

  static String? deliveryPin(Map<String, dynamic> delivery) {
    return null;
  }

  static String _sixDigitPin(Random random) {
    return (100000 + random.nextInt(900000)).toString();
  }

  static String _trigger({
    required double? declaredValueGbp,
    required bool manuallySelected,
    required String? matchedCategory,
  }) {
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
