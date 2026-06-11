import 'package:circum/app/iris/iris_item_repository.dart';
import 'package:circum/pricing/delivery_pricing.dart';

class IrisWeightLookupResult {
  final String matchedItemName;
  final int quantity;
  final double singleItemWeightKg;
  final double weightKg;
  final String weightBand;
  final String confidence;
  final double confidenceScore;
  final String explanation;
  final String packageType;
  final String weightSource;
  final String truthBand;
  final bool requiresVehicleReview;
  final ItemDimensionsCm? typicalDimensions;
  final String vehicleSuitability;
  final bool fragile;
  final bool stackable;
  final String handlingNotes;

  const IrisWeightLookupResult({
    required this.matchedItemName,
    required this.quantity,
    required this.singleItemWeightKg,
    required this.weightKg,
    required this.weightBand,
    required this.confidence,
    required this.confidenceScore,
    required this.explanation,
    required this.packageType,
    required this.weightSource,
    required this.truthBand,
    required this.requiresVehicleReview,
    required this.typicalDimensions,
    required this.vehicleSuitability,
    required this.fragile,
    required this.stackable,
    required this.handlingNotes,
  });
}

class ItemDimensionsCm {
  final double length;
  final double width;
  final double height;

  const ItemDimensionsCm({
    required this.length,
    required this.width,
    required this.height,
  });

  String get label =>
      '${length.toStringAsFixed(0)} x ${width.toStringAsFixed(0)} x ${height.toStringAsFixed(0)} cm';
}

class IrisWeightEstimator {
  static int extractQuantity(String description) {
    final text = description.trim().toLowerCase();
    if (text.isEmpty) return 1;
    final leading = RegExp(r'^\s*(\d+)\s*(?:[x×]\s*)?').firstMatch(text);
    final suffix = RegExp(r'\b[x×]\s*(\d+)\b').firstMatch(text);
    final parsed = int.tryParse(leading?.group(1) ?? suffix?.group(1) ?? '1');
    return parsed == null || parsed < 1 ? 1 : parsed;
  }

  static IrisWeightLookupResult? knownProductEstimate(String description) {
    final text = description.trim().toLowerCase();
    final quantity = extractQuantity(description);
    for (final product in _knownProducts) {
      if (product.patterns.any(text.contains)) {
        final totalWeightKg = product.weightKg * quantity;
        final band = DeliveryPricing.weightBandFor(totalWeightKg).category;
        return IrisWeightLookupResult(
          matchedItemName: product.name,
          quantity: quantity,
          singleItemWeightKg: product.weightKg,
          weightKg: totalWeightKg,
          weightBand: band,
          confidence: product.confidence,
          confidenceScore: product.confidenceScore,
          explanation: quantity == 1
              ? 'Iris matched the description to ${product.name} using Circum known-product data.'
              : 'Iris matched $quantity × ${product.name} using Circum known-product data.',
          packageType: product.packageType,
          weightSource: 'known_product_lookup',
          truthBand: product.truthBand,
          requiresVehicleReview:
              totalWeightKg > 10 || product.vehicleSuitability == 'Van',
          typicalDimensions: product.typicalDimensions,
          vehicleSuitability: product.vehicleSuitability,
          fragile: product.fragile,
          stackable: product.stackable,
          handlingNotes: product.handlingNotes,
        );
      }
    }
    final repositoryItem = IrisItemRepository.match(description);
    if (repositoryItem != null) {
      final totalWeightKg = repositoryItem.estimatedWeightKg * quantity;
      final band = DeliveryPricing.weightBandFor(totalWeightKg).category;
      final dimensions = repositoryItem.typicalDimensionsCm;
      return IrisWeightLookupResult(
        matchedItemName: repositoryItem.itemName,
        quantity: quantity,
        singleItemWeightKg: repositoryItem.estimatedWeightKg,
        weightKg: totalWeightKg,
        weightBand: band,
        confidence: repositoryItem.confidenceBaseline >= 0.85
            ? 'high'
            : repositoryItem.confidenceBaseline >= 0.65
                ? 'medium'
                : 'low',
        confidenceScore: repositoryItem.confidenceBaseline,
        explanation: quantity == 1
            ? 'Iris matched the description to ${repositoryItem.itemName} using the Circum item repository.'
            : 'Iris matched $quantity × ${repositoryItem.itemName} using the Circum item repository.',
        packageType: repositoryItem.category,
        weightSource: 'repository_match',
        truthBand: repositoryItem.confidenceBaseline >= 0.85
            ? 'Repository Match'
            : 'Medium Confidence',
        requiresVehicleReview: repositoryItem.requiresIRISReview ||
            totalWeightKg > 10 ||
            repositoryItem.vehicleSuitability == 'Van',
        typicalDimensions: ItemDimensionsCm(
          length: dimensions.lengthCm,
          width: dimensions.widthCm,
          height: dimensions.heightCm,
        ),
        vehicleSuitability: repositoryItem.vehicleSuitability,
        fragile: repositoryItem.fragile,
        stackable: repositoryItem.stackable,
        handlingNotes: repositoryItem.deliveryNotes,
      );
    }
    return null;
  }

  static bool potentialMismatchDetected({
    required String description,
    double? customerDeclaredWeightKg,
    double? irisEstimatedWeightKg,
  }) {
    final text = description.trim().toLowerCase();
    final describesSmallItem = text.contains('phone') ||
        text.contains('iphone') ||
        text.contains('airpods') ||
        text.contains('envelope') ||
        text.contains('letter') ||
        text.contains('small');
    final heaviest = [
      customerDeclaredWeightKg ?? 0,
      irisEstimatedWeightKg ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    return describesSmallItem && heaviest > 10;
  }

  static const List<_KnownIrisProduct> _knownProducts = [
    _KnownIrisProduct(
      patterns: ['iphone 13', 'apple iphone 13'],
      name: 'Apple iPhone 13',
      weightKg: 0.174,
      packageType: 'Phone',
      truthBand: 'Exact Match',
      typicalDimensions: ItemDimensionsCm(length: 15, width: 8, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['iphone 15', 'apple iphone 15'],
      name: 'Apple iPhone 15',
      weightKg: 0.171,
      packageType: 'Phone',
      truthBand: 'Exact Match',
      typicalDimensions: ItemDimensionsCm(length: 15, width: 8, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['airpods pro', 'apple airpods pro'],
      name: 'AirPods Pro',
      weightKg: 0.056,
      packageType: 'Earphones',
      truthBand: 'Exact Match',
      typicalDimensions: ItemDimensionsCm(length: 7, width: 6, height: 3),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['iphone 14', 'apple iphone 14'],
      name: 'Apple iPhone 14',
      weightKg: 0.172,
      packageType: 'Phone',
      typicalDimensions: ItemDimensionsCm(length: 15, width: 8, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Small fragile electronics package.',
    ),
    _KnownIrisProduct(
      patterns: ['macbook air 13', 'macbook air', 'macbook'],
      name: 'MacBook Air 13',
      weightKg: 1.24,
      packageType: 'Laptop',
      typicalDimensions: ItemDimensionsCm(length: 31, width: 22, height: 2),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Protect from impact and rain.',
    ),
    _KnownIrisProduct(
      patterns: ['playstation 5', 'ps5'],
      name: 'PlayStation 5',
      weightKg: 4.5,
      packageType: 'Games console',
      typicalDimensions: ItemDimensionsCm(length: 39, width: 26, height: 11),
      vehicleSuitability: 'Car',
      fragile: true,
      stackable: false,
      handlingNotes: 'Bulky electronics; keep upright and protected.',
    ),
    _KnownIrisProduct(
      patterns: ['standard laptop', 'laptop'],
      name: 'Standard laptop',
      weightKg: 2,
      packageType: 'Laptop',
      confidence: 'medium',
      confidenceScore: 0.7,
      typicalDimensions: ItemDimensionsCm(length: 36, width: 25, height: 3),
      vehicleSuitability: 'Bike',
      fragile: true,
      stackable: true,
      handlingNotes: 'Protect from impact and rain.',
    ),
    _KnownIrisProduct(
      patterns: ['tv', 'television'],
      name: 'Television',
      weightKg: 12,
      packageType: 'Large item',
      confidence: 'medium',
      confidenceScore: 0.7,
      truthBand: 'Medium Confidence',
      typicalDimensions: ItemDimensionsCm(length: 110, width: 70, height: 15),
      vehicleSuitability: 'Car or Van',
      fragile: true,
      stackable: false,
      handlingNotes: 'Screen item; vehicle depends on screen size.',
    ),
    _KnownIrisProduct(
      patterns: ['sofa', 'couch'],
      name: 'Sofa',
      weightKg: 12,
      packageType: 'Furniture',
      confidence: 'medium',
      confidenceScore: 0.7,
      truthBand: 'Medium Confidence',
      typicalDimensions: ItemDimensionsCm(length: 180, width: 90, height: 80),
      vehicleSuitability: 'Van',
      fragile: false,
      stackable: false,
      handlingNotes: 'Bulky item; van recommended even when not very heavy.',
    ),
    _KnownIrisProduct(
      patterns: ['microwave'],
      name: 'Microwave',
      weightKg: 12,
      packageType: 'Kitchen appliance',
      confidence: 'medium',
      confidenceScore: 0.7,
      truthBand: 'Medium Confidence',
      typicalDimensions: ItemDimensionsCm(length: 45, width: 35, height: 28),
      vehicleSuitability: 'Car or Van',
      fragile: true,
      stackable: false,
      handlingNotes: 'Compact but fragile appliance.',
    ),
    _KnownIrisProduct(
      patterns: ['bicycle', 'bike'],
      name: 'Bicycle',
      weightKg: 15,
      packageType: 'Large item',
      confidence: 'medium',
      confidenceScore: 0.7,
      truthBand: 'Medium Confidence',
      typicalDimensions: ItemDimensionsCm(length: 170, width: 60, height: 100),
      vehicleSuitability: 'Van',
      fragile: false,
      stackable: false,
      handlingNotes: 'Large item by dimensions; van recommended.',
    ),
    _KnownIrisProduct(
      patterns: ['shoebox', 'shoe box'],
      name: 'Standard shoebox',
      weightKg: 1,
      packageType: 'Small parcel',
      confidence: 'medium',
      confidenceScore: 0.65,
      typicalDimensions: ItemDimensionsCm(length: 34, width: 22, height: 13),
      vehicleSuitability: 'Bike',
      fragile: false,
      stackable: true,
      handlingNotes: 'Small stackable parcel.',
    ),
    _KnownIrisProduct(
      patterns: ['small parcel'],
      name: 'Small parcel',
      weightKg: 2,
      packageType: 'Small parcel',
      confidence: 'medium',
      confidenceScore: 0.65,
      typicalDimensions: ItemDimensionsCm(length: 35, width: 25, height: 15),
      vehicleSuitability: 'Bike',
      fragile: false,
      stackable: true,
      handlingNotes: 'Small general parcel.',
    ),
  ];
}

class _KnownIrisProduct {
  final List<String> patterns;
  final String name;
  final double weightKg;
  final String packageType;
  final String confidence;
  final double confidenceScore;
  final String truthBand;
  final ItemDimensionsCm? typicalDimensions;
  final String vehicleSuitability;
  final bool fragile;
  final bool stackable;
  final String handlingNotes;

  const _KnownIrisProduct({
    required this.patterns,
    required this.name,
    required this.weightKg,
    required this.packageType,
    this.confidence = 'high',
    this.confidenceScore = 0.9,
    this.truthBand = 'Very High Confidence',
    this.typicalDimensions,
    this.vehicleSuitability = 'Bike',
    this.fragile = false,
    this.stackable = true,
    this.handlingNotes = '',
  });
}
