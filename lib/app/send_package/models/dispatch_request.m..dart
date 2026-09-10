import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'contact_info.m.dart';

class DispatchRequest extends Equatable {
  final RideContactInfo pickupData;
  final RideContactInfo dropoffData;
  final String requestId;
  final String code;
  final double price;
  final String currency;
  final Timestamp? createdAt;
  final String? riderName;
  final double? userRating;
  final double? riderRating;
  final double? riderPayout;
  final double? riderEarning;
  final double? driverPayout;
  final String? distanceText;
  final String? durationText;
  final String? pickupWindow;
  final String? serviceType;
  final bool isBusiness;
  final bool isHealthPlus;
  final bool requiresVanguard;
  final int trustPoints;
  const DispatchRequest(
      {required this.pickupData,
      required this.dropoffData,
      required this.requestId,
      required this.code,
      required this.price,
      required this.currency,
      this.createdAt,
      this.riderName,
      this.userRating,
      this.riderRating,
      this.riderPayout,
      this.riderEarning,
      this.driverPayout,
      this.distanceText,
      this.durationText,
      this.pickupWindow,
      this.serviceType,
      this.isBusiness = false,
      this.isHealthPlus = false,
      this.requiresVanguard = false,
      this.trustPoints = 0});

  @override
  List<Object> get props => [
        {pickupData},
        {dropoffData},
        {requestId},
        {code},
        {price},
        {createdAt},
        {riderName},
        {userRating},
        {riderRating},
        {riderPayout},
        {riderEarning},
        {driverPayout},
        {distanceText},
        {durationText},
        {pickupWindow},
        {serviceType},
        {isBusiness},
        {isHealthPlus},
        {requiresVanguard},
        {trustPoints},
      ];

  static DispatchRequest fromJson(dynamic json) {
    return DispatchRequest(
      pickupData: RideContactInfo.fromJson(json['pickupDetails']),
      dropoffData: RideContactInfo.fromJson(json['dropoffDetails']),
      requestId: json['requestId'],
      code: json['code'],
      price: (json['price'] as num).toDouble(),
      currency: json['currency'],
      createdAt: json['createdAt'],
      riderName: json['riderName'],
      userRating: json['userRating'],
      riderRating: json['riderRating'],
      riderPayout: (json['riderPayout'] as num?)?.toDouble(),
      riderEarning: (json['riderEarning'] as num?)?.toDouble(),
      driverPayout: (json['driverPayout'] as num?)?.toDouble(),
      distanceText: json['distanceText'] as String?,
      durationText: json['durationText'] as String?,
      pickupWindow:
          (json['pickupWindow'] ?? json['scheduledPickupWindow']) as String?,
      serviceType: json['serviceType'] as String?,
      isBusiness:
          json['isBusiness'] == true || json['businessDelivery'] == true,
      isHealthPlus: json['isHealthPlus'] == true,
      requiresVanguard:
          json['requiresVanguard'] == true || json['isVanguard'] == true,
      trustPoints: (json['trustPoints'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() => '''DispatchRequests { 
      pickupData: $pickupData, 
      dropoffData: $dropoffData,
      price: $price
      }
''';
}
