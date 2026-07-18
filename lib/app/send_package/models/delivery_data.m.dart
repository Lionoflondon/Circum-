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
  final String? deliveryPin;

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
      this.photoURL,
      this.deliveryPin});

  factory DeliveryData.fromJson(data) {
    final vanguardProtection = data['vanguardProtection'] is Map
        ? data['vanguardProtection'] as Map
        : null;
    final collectionPin =
        '${data['collectionPin'] ?? vanguardProtection?['collectionPin'] ?? data['code'] ?? ''}'
            .trim();
    return DeliveryData(
        courierName:
            '${data['courierName'] ?? data['riderName'] ?? data['driverName'] ?? 'Your rider'}',
        phoneNumber: '${data['phoneNumber'] ?? data['riderPhone'] ?? ''}',
        locality: data['locality'],
        typeOfVehicle:
            '${data['typeOfVehicle'] ?? data['driverVehicle'] ?? 'Rider'}',
        estimatedDeliveryTime:
            '${data['estimatedDeliveryTime'] ?? data['eta'] ?? ''}',
        code: collectionPin,
        rating: '${data['rating'] ?? data['riderRating'] ?? ''}',
        plateNumber:
            '${data['plateNumber'] ?? data['driverPlateNumber'] ?? ''}',
        riderId:
            '${data['riderId'] ?? data['driverId'] ?? data['assignedRiderId'] ?? ''}',
        photoURL: data['photoURL'] != 'null' ? data['photoURL'] : null,
        deliveryPin:
            '${data['deliveryPin'] ?? vanguardProtection?['deliveryPin'] ?? ''}'
                .trim());
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
      if (deliveryPin != null && deliveryPin!.isNotEmpty)
        'deliveryPin': deliveryPin,
    };
  }
}
