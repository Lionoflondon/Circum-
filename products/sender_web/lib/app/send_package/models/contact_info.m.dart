import 'package:cloud_firestore/cloud_firestore.dart';

class RideContactInfo {
  final String? fullname;
  final PositionData position;
  final String? phoneNumber;
  final String? moreInformation;
  final String? locality;
  final String? address;
  final String? subAddress;

  RideContactInfo(
      {this.fullname,
      required this.position,
      this.phoneNumber,
      this.moreInformation,
      this.locality,
      this.address,
      this.subAddress});

  factory RideContactInfo.fromJson(dynamic json) {
    return RideContactInfo(
      fullname: json['fullname'],
      position: PositionData.fromJson(json['position']),
      phoneNumber: json['phone'],
      moreInformation: json['moreInformation'],
      locality: json['locality'],
      address: json['address'],
      subAddress: json['subAddress'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fullname': fullname,
      'position': position,
      'phoneNumber': phoneNumber,
      'moreInformation': moreInformation,
      'locality': locality,
      'address': address,
      'subAddress': subAddress
    };
  }
}

class PositionData {
  final String geohash;
  final GeoPoint geopoint;

  PositionData({
    required this.geohash,
    required this.geopoint,
  });

  factory PositionData.fromJson(dynamic json) {
    return PositionData(geohash: json['geohash'], geopoint: json['geopoint']);
  }

  Map<String, dynamic> toJson() {
    return {'geohash': geohash, 'geopoint': geopoint};
  }
}
