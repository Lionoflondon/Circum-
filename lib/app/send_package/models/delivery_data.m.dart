class DeliveryData {
  final String courierName;
  final String phoneNumber;
  final String? locality;
  final String typeOfVehicle;
  final String plateNumber;
  final String estimatedDeliveryTime;
  final String code;
  final String rating;
  final String riderId;
  final String? photoURL;

  DeliveryData(
      {required this.courierName,
      required this.phoneNumber,
      this.locality,
      required this.typeOfVehicle,
      required this.estimatedDeliveryTime,
      required this.plateNumber,
      required this.code,
      required this.rating,
      required this.riderId,
      this.photoURL});

  factory DeliveryData.fromJson(data) {
    return DeliveryData(
        courierName:
            '${data['courierName'] ?? data['riderName'] ?? data['driverName'] ?? 'Your Circum Rider'}',
        phoneNumber: '${data['phoneNumber'] ?? data['riderPhone'] ?? ''}',
        locality: data['locality'],
        typeOfVehicle:
            '${data['typeOfVehicle'] ?? data['driverVehicle'] ?? 'Circum Rider'}',
        estimatedDeliveryTime:
            '${data['estimatedDeliveryTime'] ?? data['eta'] ?? ''}',
        code: '${data['code'] ?? ''}'.trim(),
        rating: '${data['rating'] ?? data['riderRating'] ?? ''}',
        plateNumber:
            '${data['plateNumber'] ?? data['driverPlateNumber'] ?? ''}',
        riderId:
            '${data['riderId'] ?? data['driverId'] ?? data['assignedRiderId'] ?? ''}',
        photoURL: data['photoURL'] != 'null' ? data['photoURL'] : null);
  }

  Map<String, dynamic> toJson() {
    return {
      'courierName': courierName,
      'phoneNumber': phoneNumber,
      'locality': locality,
      'typeOfVehicle': typeOfVehicle,
      'estimatedDeliveryTime': estimatedDeliveryTime,
      'code': code,
      'rating': rating,
      'plateNumber': plateNumber,
      'riderId': riderId,
    };
  }
}
