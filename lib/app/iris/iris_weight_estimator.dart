import 'package:circum/pricing/delivery_pricing.dart';

class IrisWeightLookupResult {
  final double weightKg;
  final String weightBand;
  final String confidence;
  final double confidenceScore;
  final String explanation;
  final String packageType;
  final String weightSource;
  final String truthBand;
  final bool requiresVehicleReview;

  const IrisWeightLookupResult({
    required this.weightKg,
    required this.weightBand,
    required this.confidence,
    required this.confidenceScore,
    required this.explanation,
    required this.packageType,
    required this.weightSource,
    required this.truthBand,
    required this.requiresVehicleReview,
  });
}

class IrisWeightEstimator {
  static IrisWeightLookupResult? knownProductEstimate(String description) {
    final text = description.trim().toLowerCase();
    for (final product in _knownProducts) {
      if (product.patterns.any(text.contains)) {
        final band = DeliveryPricing.weightBandFor(product.weightKg).category;
        return IrisWeightLookupResult(
          weightKg: product.weightKg,
          weightBand: band,
          confidence: product.confidence,
          confidenceScore: product.confidenceScore,
          explanation:
              'Iris matched the description to ${product.name} using Circum known-product data.',
          packageType: product.packageType,
          weightSource: 'known_product_lookup',
          truthBand: product.truthBand,
          requiresVehicleReview: product.weightKg > 10,
        );
      }
    }
    return null;
  }

  static const List<_KnownIrisProduct> _knownProducts = [
    _KnownIrisProduct(
      patterns: ['iphone 13', 'apple iphone 13'],
      name: 'Apple iPhone 13',
      weightKg: 0.174,
      packageType: 'Phone',
      truthBand: 'Exact Match',
    ),
    _KnownIrisProduct(
      patterns: ['iphone 15', 'apple iphone 15'],
      name: 'Apple iPhone 15',
      weightKg: 0.171,
      packageType: 'Phone',
      truthBand: 'Exact Match',
    ),
    _KnownIrisProduct(
      patterns: ['airpods pro', 'apple airpods pro'],
      name: 'AirPods Pro',
      weightKg: 0.056,
      packageType: 'Earphones',
      truthBand: 'Exact Match',
    ),
    _KnownIrisProduct(
      patterns: ['iphone 14', 'apple iphone 14'],
      name: 'Apple iPhone 14',
      weightKg: 0.172,
      packageType: 'Phone',
    ),
    _KnownIrisProduct(
      patterns: ['macbook air 13', 'macbook air'],
      name: 'MacBook Air 13',
      weightKg: 1.24,
      packageType: 'Laptop',
    ),
    _KnownIrisProduct(
      patterns: ['playstation 5', 'ps5'],
      name: 'PlayStation 5',
      weightKg: 4.5,
      packageType: 'Games console',
    ),
    _KnownIrisProduct(
      patterns: ['standard laptop', 'laptop'],
      name: 'Standard laptop',
      weightKg: 2,
      packageType: 'Laptop',
      confidence: 'medium',
      confidenceScore: 0.7,
    ),
    _KnownIrisProduct(
      patterns: ['shoebox', 'shoe box'],
      name: 'Standard shoebox',
      weightKg: 1,
      packageType: 'Small parcel',
      confidence: 'medium',
      confidenceScore: 0.65,
    ),
    _KnownIrisProduct(
      patterns: ['small parcel'],
      name: 'Small parcel',
      weightKg: 2,
      packageType: 'Small parcel',
      confidence: 'medium',
      confidenceScore: 0.65,
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

  const _KnownIrisProduct({
    required this.patterns,
    required this.name,
    required this.weightKg,
    required this.packageType,
    this.confidence = 'high',
    this.confidenceScore = 0.9,
    this.truthBand = 'Very High Confidence',
  });
}
