class DriverVehicle {
  final String type;
  final String makeModel;
  final String colour;
  final String plateNumber;

  const DriverVehicle({
    required this.type,
    required this.makeModel,
    required this.colour,
    required this.plateNumber,
  });

  factory DriverVehicle.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return DriverVehicle(
      type: _readString(map, ['type', 'vehicleType', 'typeOfVehicle']),
      makeModel: _readString(map, ['makeModel', 'vehicleMakeModel']),
      colour: _readString(map, ['colour', 'color', 'vehicleColour']),
      plateNumber: _readString(map, ['plateNumber', 'registration']),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'makeModel': makeModel,
        'colour': colour,
        'plateNumber': plateNumber,
      };

  String get summary {
    final parts = [colour, makeModel, type]
        .where((part) => part.trim().isNotEmpty)
        .join(' ');
    return parts.trim().isEmpty ? 'Vehicle details pending' : parts;
  }
}

class DriverProfile {
  final String driverId;
  final String fullName;
  final String? photoUrl;
  final String phoneNumber;
  final String verificationStatus;
  final String status;
  final DriverVehicle vehicle;
  final DriverPerformanceMetric performance;
  final List<DriverRating> recentRatings;

  const DriverProfile({
    required this.driverId,
    required this.fullName,
    required this.photoUrl,
    required this.phoneNumber,
    required this.verificationStatus,
    required this.status,
    required this.vehicle,
    required this.performance,
    this.recentRatings = const [],
  });

  factory DriverProfile.fromMap(
    String driverId,
    Map<String, dynamic>? data, {
    DriverPerformanceMetric? performance,
    List<DriverRating> recentRatings = const [],
  }) {
    final map = data ?? const <String, dynamic>{};
    return DriverProfile(
      driverId: driverId,
      fullName:
          _readString(map, ['fullName', 'name'], fallback: 'Circum rider'),
      photoUrl: _readNullableString(map, ['photoUrl', 'profilePhotoUrl']),
      phoneNumber: _readString(map, ['phoneNumber', 'phone']),
      verificationStatus:
          _readString(map, ['verificationStatus'], fallback: 'pending'),
      status: _readString(map, ['driverStatus', 'status'], fallback: 'active'),
      vehicle: DriverVehicle.fromMap({
        ...map,
        if (map['vehicle'] is Map<String, dynamic>)
          ...(map['vehicle'] as Map<String, dynamic>),
      }),
      performance: performance ?? DriverPerformanceMetric.empty(driverId),
      recentRatings: recentRatings,
    );
  }
}

class DriverRating {
  static const complaintTags = {
    'late',
    'poor_communication',
  };

  final String driverId;
  final String customerId;
  final String deliveryId;
  final int starRating;
  final String feedbackText;
  final List<String> feedbackTags;
  final bool hiddenByAdmin;

  const DriverRating({
    required this.driverId,
    required this.customerId,
    required this.deliveryId,
    required this.starRating,
    this.feedbackText = '',
    this.feedbackTags = const [],
    this.hiddenByAdmin = false,
  });

  factory DriverRating.fromMap(Map<String, dynamic> data) {
    return DriverRating(
      driverId: '${data['driverId'] ?? data['riderId'] ?? ''}',
      customerId: '${data['customerId'] ?? ''}',
      deliveryId: '${data['deliveryId'] ?? data['tripId'] ?? ''}',
      starRating: (data['starRating'] as num? ?? data['rating'] as num? ?? 0)
          .round()
          .clamp(0, 5),
      feedbackText: '${data['feedbackText'] ?? ''}',
      feedbackTags: (data['feedbackTags'] as List<dynamic>? ?? const [])
          .map((tag) => '$tag')
          .toList(),
      hiddenByAdmin: data['hiddenByAdmin'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'driverId': driverId,
        'customerId': customerId,
        'deliveryId': deliveryId,
        'starRating': starRating,
        'feedbackText': feedbackText,
        'feedbackTags': feedbackTags,
        'hiddenByAdmin': hiddenByAdmin,
      };

  static String documentId({
    required String deliveryId,
    required String customerId,
  }) {
    return '${_safeDocumentPart(deliveryId)}_${_safeDocumentPart(customerId)}';
  }

  bool get isComplaint =>
      starRating <= 2 || feedbackTags.any(complaintTags.contains);
}

class DriverPerformanceMetric {
  final String driverId;
  final double averageRating;
  final int totalRatings;
  final Map<int, int> ratingDistribution;
  final int completedTrips;
  final int cancelledTrips;
  final int lateDeliveries;
  final int failedDeliveries;
  final int complaints;
  final double recentRatingTrend;
  final double qualityScore;
  final String driverStatus;

  const DriverPerformanceMetric({
    required this.driverId,
    required this.averageRating,
    required this.totalRatings,
    required this.ratingDistribution,
    required this.completedTrips,
    required this.cancelledTrips,
    required this.lateDeliveries,
    required this.failedDeliveries,
    required this.complaints,
    required this.recentRatingTrend,
    required this.qualityScore,
    required this.driverStatus,
  });

  factory DriverPerformanceMetric.empty(String driverId) {
    return DriverPerformanceMetric(
      driverId: driverId,
      averageRating: 0,
      totalRatings: 0,
      ratingDistribution: const {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
      completedTrips: 0,
      cancelledTrips: 0,
      lateDeliveries: 0,
      failedDeliveries: 0,
      complaints: 0,
      recentRatingTrend: 0,
      qualityScore: 0,
      driverStatus: 'active',
    );
  }

  factory DriverPerformanceMetric.fromMap(
      String driverId, Map<String, dynamic>? data) {
    if (data == null) return DriverPerformanceMetric.empty(driverId);
    final distributionData =
        data['ratingDistribution'] as Map<String, dynamic>? ?? const {};
    return DriverPerformanceMetric(
      driverId: driverId,
      averageRating: (data['averageRating'] as num? ?? 0).toDouble(),
      totalRatings: (data['totalRatings'] as num? ?? 0).toInt(),
      ratingDistribution: {
        for (var star = 1; star <= 5; star++)
          star: (distributionData['$star'] as num? ?? 0).toInt(),
      },
      completedTrips: (data['completedTrips'] as num? ?? 0).toInt(),
      cancelledTrips: (data['cancelledTrips'] as num? ?? 0).toInt(),
      lateDeliveries: (data['lateDeliveries'] as num? ?? 0).toInt(),
      failedDeliveries: (data['failedDeliveries'] as num? ?? 0).toInt(),
      complaints: (data['complaints'] as num? ?? 0).toInt(),
      recentRatingTrend: (data['recentRatingTrend'] as num? ?? 0).toDouble(),
      qualityScore: (data['qualityScore'] as num? ?? 0).toDouble(),
      driverStatus: '${data['driverStatus'] ?? 'active'}',
    );
  }

  Map<String, dynamic> toJson() => {
        'driverId': driverId,
        'averageRating': averageRating,
        'totalRatings': totalRatings,
        'ratingDistribution': {
          for (var star = 1; star <= 5; star++)
            '$star': ratingDistribution[star] ?? 0,
        },
        'completedTrips': completedTrips,
        'cancelledTrips': cancelledTrips,
        'lateDeliveries': lateDeliveries,
        'failedDeliveries': failedDeliveries,
        'complaints': complaints,
        'recentRatingTrend': recentRatingTrend,
        'qualityScore': qualityScore,
        'driverStatus': driverStatus,
      };

  int get poorRatingCount =>
      (ratingDistribution[1] ?? 0) + (ratingDistribution[2] ?? 0);
}

class DriverPerformanceInput {
  final String driverId;
  final List<DriverRating> ratings;
  final int completedTrips;
  final int cancelledTrips;
  final int lateDeliveries;
  final int failedDeliveries;
  final int complaints;

  const DriverPerformanceInput({
    required this.driverId,
    required this.ratings,
    required this.completedTrips,
    this.cancelledTrips = 0,
    this.lateDeliveries = 0,
    this.failedDeliveries = 0,
    this.complaints = 0,
  });
}

class DriverPerformanceService {
  static DriverPerformanceMetric calculate(DriverPerformanceInput input) {
    final distribution = {for (var star = 1; star <= 5; star++) star: 0};
    var ratingTotal = 0;
    for (final rating in input.ratings) {
      final star = rating.starRating.clamp(1, 5);
      distribution[star] = (distribution[star] ?? 0) + 1;
      ratingTotal += star;
    }

    final totalRatings = input.ratings.length;
    final averageRating = totalRatings == 0 ? 0.0 : ratingTotal / totalRatings;
    final recentTrend = _recentTrend(input.ratings);
    final status = driverStatusFor(
      averageRating: averageRating,
      complaints: input.complaints,
      poorRatings: (distribution[1] ?? 0) + (distribution[2] ?? 0),
    );

    return DriverPerformanceMetric(
      driverId: input.driverId,
      averageRating: _round2(averageRating),
      totalRatings: totalRatings,
      ratingDistribution: distribution,
      completedTrips: input.completedTrips,
      cancelledTrips: input.cancelledTrips,
      lateDeliveries: input.lateDeliveries,
      failedDeliveries: input.failedDeliveries,
      complaints: input.complaints,
      recentRatingTrend: _round2(recentTrend),
      qualityScore: _round2(
        qualityScore(
          averageRating: averageRating,
          completedTrips: input.completedTrips,
          cancelledTrips: input.cancelledTrips,
          lateDeliveries: input.lateDeliveries,
          failedDeliveries: input.failedDeliveries,
          complaints: input.complaints,
        ),
      ),
      driverStatus: status,
    );
  }

  static double qualityScore({
    required double averageRating,
    required int completedTrips,
    required int cancelledTrips,
    required int lateDeliveries,
    required int failedDeliveries,
    required int complaints,
  }) {
    if (completedTrips <= 0 && averageRating <= 0) return 0;
    final ratingComponent = (averageRating.clamp(0, 5) / 5) * 70;
    final experienceComponent = (completedTrips.clamp(0, 200) / 200) * 15;
    final totalTrips = completedTrips + cancelledTrips + failedDeliveries;
    final cancellationRate = totalTrips == 0 ? 0 : cancelledTrips / totalTrips;
    final lateRate = completedTrips == 0 ? 0 : lateDeliveries / completedTrips;
    final failedRate = totalTrips == 0 ? 0 : failedDeliveries / totalTrips;
    final complaintRate = completedTrips == 0 ? 0 : complaints / completedTrips;
    final penalty = cancellationRate * 10 +
        lateRate * 8 +
        failedRate * 12 +
        complaintRate * 15;
    return (ratingComponent + experienceComponent - penalty).clamp(0, 100);
  }

  static String driverStatusFor({
    required double averageRating,
    int complaints = 0,
    int poorRatings = 0,
  }) {
    if (complaints >= 3 || poorRatings >= 5) return 'suspended_review';
    if (averageRating <= 0) return 'active';
    if (averageRating < 3.5) return 'under_review';
    if (averageRating < 4.0) return 'needs_monitoring';
    if (averageRating < 4.5) return 'good';
    return 'excellent';
  }

  static bool shouldFlagLowRatedDriver(DriverPerformanceMetric metric) {
    return metric.averageRating < 3.5 ||
        metric.poorRatingCount >= 3 ||
        metric.complaints >= 2 ||
        metric.driverStatus == 'under_review' ||
        metric.driverStatus == 'suspended_review';
  }

  static double _recentTrend(List<DriverRating> ratings) {
    if (ratings.length < 2) return 0;
    final recent = ratings.take(5).toList();
    final older = ratings.skip(5).take(5).toList();
    if (older.isEmpty) return 0;
    final recentAverage =
        recent.map((rating) => rating.starRating).reduce((a, b) => a + b) /
            recent.length;
    final olderAverage =
        older.map((rating) => rating.starRating).reduce((a, b) => a + b) /
            older.length;
    return recentAverage - olderAverage;
  }

  static double _round2(double value) => (value * 100).roundToDouble() / 100;
}

String _safeDocumentPart(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'unknown';
  return trimmed.replaceAll(RegExp(r'[/#?\[\]]'), '-');
}

String _readString(
  Map<String, dynamic> data,
  List<String> keys, {
  String fallback = '',
}) {
  return _readNullableString(data, keys) ?? fallback;
}

String? _readNullableString(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && '$value'.trim().isNotEmpty) return '$value';
  }
  return null;
}
