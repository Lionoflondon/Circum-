part of 'send_package_bloc.dart';

class SendPackageState {
  List<Suggestion> suggestions;
  String? pickupLocation;
  String? destinationLocation;
  String? pickupLocationSubAddress;
  String? destinationLocationSubAddress;
  PlaceCoordinate? pickupCoordinate;
  PlaceCoordinate? desinationCoordinate;
  double? distance;

  SendPackageState(
      {this.suggestions = const [],
      this.pickupLocation,
      this.destinationLocation,
      this.pickupLocationSubAddress,
      this.destinationLocationSubAddress,
      this.pickupCoordinate,
      this.desinationCoordinate,
      this.distance});

  SendPackageState copyWith(
      {List<Suggestion>? suggestions,
      String? pickupLocation,
      String? destinationLocation,
      String? pickupLocationSubAddress,
      String? destinationLocationSubAddress,
      PlaceCoordinate? pickupCoordinate,
      PlaceCoordinate? desinationCoordinate,
      double? distance}) {
    return SendPackageState(
        suggestions: suggestions ?? this.suggestions,
        pickupLocation: pickupLocation ?? this.pickupLocation,
        destinationLocation: destinationLocation ?? this.destinationLocation,
        pickupLocationSubAddress:
            pickupLocationSubAddress ?? this.pickupLocationSubAddress,
        destinationLocationSubAddress:
            destinationLocationSubAddress ?? this.destinationLocationSubAddress,
        pickupCoordinate: pickupCoordinate ?? this.pickupCoordinate,
        desinationCoordinate: desinationCoordinate ?? this.desinationCoordinate,
        distance: distance ?? this.distance);
  }
}
