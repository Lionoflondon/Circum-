class CanonicalIrisResult {
  final String itemName;
  final int quantity;
  final double? unitWeightKg;
  final double? totalWeightKg;
  final double? irisSuggestedWeightKg;
  final String? category;
  final String? weightBand;
  final String? recommendedVehicle;
  final String confidenceLabel;
  final String? repositoryMatch;
  final int? similarVerifiedDeliveries;
  final String? explanation;
  final List<String> handlingRequirements;
  final List<String> reasons;
  final bool partial;
  final bool vanguardRequired;
  final String? vanguardRequiredReason;

  const CanonicalIrisResult({
    required this.itemName,
    required this.quantity,
    required this.confidenceLabel,
    this.unitWeightKg,
    this.totalWeightKg,
    this.irisSuggestedWeightKg,
    this.category,
    this.weightBand,
    this.recommendedVehicle,
    this.repositoryMatch,
    this.similarVerifiedDeliveries,
    this.explanation,
    this.handlingRequirements = const [],
    this.reasons = const [],
    this.partial = false,
    this.vanguardRequired = false,
    this.vanguardRequiredReason,
  });

  String get itemAndQuantity =>
      '${itemName.isEmpty ? 'Parcel' : itemName} ×$quantity';

  String get totalWeightLabel => totalWeightKg == null
      ? 'Unavailable'
      : '${totalWeightKg!.toStringAsFixed(2)} kg';

  String get unitWeightLabel => unitWeightKg == null
      ? 'Unavailable'
      : '${unitWeightKg!.toStringAsFixed(2)} kg';

  factory CanonicalIrisResult.fromCallable(
    Map<String, dynamic> data, {
    String fallbackItemName = '',
    int fallbackQuantity = 1,
  }) {
    final recommendation = _map(data['recommendation']);
    final weightBand = recommendation['weightBand'];
    final repository = _map(data['repositoryMatch']);
    final internal = _map(data['internal']);
    final weightAuthority = _map(internal['weightAuthority']);
    final riderMatching = _map(internal['riderMatching']);
    final vanguard = _map(data['vanguard']);
    final requiresVanguard = _bool(
      data['requiresVanguard'] ??
          data['vanguardRequired'] ??
          recommendation['requiresVanguard'] ??
          recommendation['vanguardRecommended'] ??
          data['vanguardRecommended'] ??
          vanguard['recommended'] ??
          vanguard['required'],
    );
    final handlingRequirements = _list(
      recommendation['handlingFlags'] ??
          recommendation['handlingRequirements'] ??
          data['handlingFlags'] ??
          data['handlingRequirements'],
    ).where((item) => item.trim().isNotEmpty).toList(growable: false);
    final reasons = [
      ..._list(data['reasons']),
      if (recommendation['customerSafeExplanation'] != null)
        '${recommendation['customerSafeExplanation']}',
    ].where((item) => item.trim().isNotEmpty).toList();
    final quantity = _int(data['quantity'] ?? recommendation['quantity']) ??
        (fallbackQuantity <= 0 ? 1 : fallbackQuantity);
    final totalWeight = _double(
      data['totalWeightKg'] ??
          recommendation['totalWeightKg'] ??
          recommendation['estimatedWeightKg'],
    );
    final unitWeight = _double(
      data['unitWeightKg'] ??
          recommendation['unitWeightKg'] ??
          (quantity > 1 && totalWeight != null ? totalWeight / quantity : null),
    );
    return CanonicalIrisResult(
      itemName:
          '${data['itemName'] ?? recommendation['detectedItem'] ?? fallbackItemName}'
              .trim(),
      quantity: quantity,
      unitWeightKg: unitWeight,
      totalWeightKg: totalWeight,
      irisSuggestedWeightKg: _double(weightAuthority['irisEstimatedWeightKg']),
      category: '${recommendation['category'] ?? ''}'.trim(),
      weightBand: weightBand is Map
          ? '${weightBand['label'] ?? ''}'.trim()
          : '${weightBand ?? ''}'.trim(),
      recommendedVehicle:
          '${data['recommendedVehicle'] ?? recommendation['recommendedVehicle'] ?? riderMatching['vehicleRequired'] ?? riderMatching['minimumVehicle'] ?? ''}'
              .trim(),
      confidenceLabel: _confidenceLabel(
        data['confidence'] ??
            recommendation['confidencePercent'] ??
            data['confidencePercent'],
      ),
      repositoryMatch:
          '${repository['canonicalName'] ?? repository['matchedItemName'] ?? repository['name'] ?? ''}'
              .trim(),
      similarVerifiedDeliveries: _int(
        data['similarVerifiedDeliveries'] ??
            internal['learningMatchedExamples'],
      ),
      explanation: '${recommendation['customerSafeExplanation'] ?? ''}'.trim(),
      handlingRequirements: handlingRequirements,
      reasons: reasons,
      partial: totalWeight == null ||
          '${data['recommendedVehicle'] ?? recommendation['recommendedVehicle'] ?? riderMatching['vehicleRequired'] ?? ''}'
              .trim()
              .isEmpty,
      vanguardRequired: requiresVanguard,
      vanguardRequiredReason:
          '${vanguard['reason'] ?? recommendation['vanguardReason'] ?? ''}'
              .trim(),
    );
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static List<String> _list(Object? value) =>
      value is Iterable ? value.map((item) => '$item').toList() : const [];

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static int? _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  static bool _bool(Object? value) {
    if (value is bool) return value;
    final normalized = '$value'.trim().toLowerCase();
    return normalized == 'true' ||
        normalized == 'required' ||
        normalized == 'recommended';
  }

  static String _confidenceLabel(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      final normalized = value.trim().toLowerCase();
      if (normalized.contains('high')) return 'High';
      if (normalized.contains('low')) return 'Low';
      if (normalized.contains('medium')) return 'Medium';
    }
    final number = _double(value);
    if (number == null) return 'Medium';
    final score = number <= 1 ? number * 100 : number;
    return '${score.round()}%';
  }
}
