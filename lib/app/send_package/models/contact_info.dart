import '../repo/place_api.dart';

class ContactInfo {
  final String? fullname;
  final PlaceCoordinate address;
  final String? phoneNumber;
  final String? moreInformation;
  final String? locality;

  ContactInfo(
      {this.fullname,
      required this.address,
      this.phoneNumber,
      this.moreInformation,
      this.locality});

  factory ContactInfo.fromJson(
      {String? fullname,
      required PlaceCoordinate address,
      String? phoneNumber,
      String? moreInformation,
      String? locality}) {
    return ContactInfo(
        fullname: fullname,
        address: address,
        phoneNumber: phoneNumber,
        moreInformation: moreInformation,
        locality: locality);
  }

  Map<String, dynamic> toJson() {
    return {
      'fullname': fullname,
      'address': address,
      'phoneNumber': phoneNumber,
      'moreInformation': moreInformation,
      'locality': locality,
    };
  }
}
