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
  const DispatchRequest({
    required this.pickupData,
    required this.dropoffData,
    required this.requestId,
    required this.code,
    required this.price,
    required this.currency,
    this.createdAt,
    this.riderName,
    this.userRating,
    this.riderRating,
  });

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
  ];

  static DispatchRequest fromJson(dynamic json) {
    return DispatchRequest(
      pickupData: RideContactInfo.fromJson(json['pickupDetails']),
      dropoffData: RideContactInfo.fromJson(json['dropoffDetails']),
      requestId: json['requestId'],
      code: json['code'],
      price: json['price'],
      currency: json['currency'],
      createdAt: json['createdAt'],
      riderName: json['riderName'],
      userRating: json['userRating'],
      riderRating: json['riderRating'],
    );
  }

  @override
  String toString() =>
      '''DispatchRequests { 
      pickupData: $pickupData, 
      dropoffData: $dropoffData,
      price: $price
      }
''';
}
