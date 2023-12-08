part of 'send_package_bloc.dart';

enum DeliveryStatus {
  inital,
  addressesSelected,
  deliveryConfirmed,
  deliveryOnGoing,
  deliveryCompleted
}

enum ParcelStatus { requested, accepted, outForDelivery, delivered }

// default MapCameraStatus is initial, lat 0, lng 0
enum MapCameraStatus {
  initialized,
  showingDeviceLocation,
  showingSourceAndDestinationLocations
}

enum SourceAndDestinationStatus { unselected, selected }

class SendPackageState {
  List<Suggestion> suggestions;
  List ongoingRequests;
  String? pickupLocation;
  String? destinationLocation;
  String? pickupLocationSubAddress;
  String? destinationLocationSubAddress;
  PlaceCoordinate? pickupCoordinate;
  PlaceCoordinate? desinationCoordinate;
  double? distance;
  final DeliveryStatus deliveryStatus;
  ContactInfo? pickupDetails;
  ContactInfo? dropoffDetails;
  String? pickupLocality;
  String? destinationLocality;
  double? price;
  DeliveryData? deliveryData;
  Map<MarkerId, Marker> markers;
  List<Polyline> polylines;
  List<LatLng> polylineCoordinates;
  SourceAndDestinationStatus sourceAndDestinationStatus;
  MapCameraStatus mapCameraStatus;
  SendPackageState(
      {this.suggestions = const [],
      this.ongoingRequests = const [],
      this.pickupLocation,
      this.destinationLocation,
      this.pickupLocationSubAddress,
      this.destinationLocationSubAddress,
      this.pickupCoordinate,
      this.desinationCoordinate,
      this.distance,
      this.deliveryStatus = DeliveryStatus.inital,
      this.pickupDetails,
      this.dropoffDetails,
      this.pickupLocality,
      this.destinationLocality,
      this.price,
      this.deliveryData,
      this.markers = const {},
      this.polylines = const [],
      this.polylineCoordinates = const [],
      this.sourceAndDestinationStatus = SourceAndDestinationStatus.unselected,
      this.mapCameraStatus = MapCameraStatus.initialized});

  SendPackageState copyWith(
      {List<Suggestion>? suggestions,
      String? pickupLocation,
      String? destinationLocation,
      String? pickupLocationSubAddress,
      String? destinationLocationSubAddress,
      PlaceCoordinate? pickupCoordinate,
      PlaceCoordinate? desinationCoordinate,
      double? distance,
      DeliveryStatus? deliveryStatus,
      List? ongoingRequests,
      ContactInfo? pickupDetails,
      ContactInfo? dropoffDetails,
      String? pickupLocality,
      String? destinationLocality,
      double? price,
      DeliveryData? deliveryData,
      Map<MarkerId, Marker>? markers,
      List<Polyline>? polylines,
      List<LatLng>? polylineCoordinates,
      SourceAndDestinationStatus? sourceAndDestinationStatus,
      MapCameraStatus? mapCameraStatus}) {
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
        distance: distance ?? this.distance,
        deliveryStatus: deliveryStatus ?? this.deliveryStatus,
        ongoingRequests: ongoingRequests ?? this.ongoingRequests,
        pickupDetails: pickupDetails ?? this.pickupDetails,
        dropoffDetails: dropoffDetails ?? this.dropoffDetails,
        pickupLocality: pickupLocality ?? this.pickupLocality,
        destinationLocality: destinationLocality ?? this.destinationLocality,
        price: price ?? this.price,
        deliveryData: deliveryData ?? this.deliveryData,
        markers: markers ?? this.markers,
        polylines: polylines ?? this.polylines,
        polylineCoordinates: polylineCoordinates ?? this.polylineCoordinates,
        sourceAndDestinationStatus:
            sourceAndDestinationStatus ?? this.sourceAndDestinationStatus,
        mapCameraStatus: mapCameraStatus ?? this.mapCameraStatus);
  }
}
