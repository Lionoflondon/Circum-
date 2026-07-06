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
    return DeliveryData(
        courierName: data['courierName'],
        phoneNumber: data['phoneNumber'],
        locality: data['locality'],
        typeOfVehicle: data['typeOfVehicle'],
        estimatedDeliveryTime: data['estimatedDeliveryTime'],
        code: data['code'],
        rating: data['rating'],
        plateNumber: data['plateNumber'],
        riderId: data['riderId'],
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
