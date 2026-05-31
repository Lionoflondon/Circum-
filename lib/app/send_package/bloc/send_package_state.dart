part of 'send_package_bloc.dart';

enum DeliveryStatus {
  inital,
  addressesSelected,
  deliveryConfirmed,
  deliveryOnGoing,
  deliveryCompleted,
  reconnectingWithRider
}

enum ParcelStatus { requested, accepted, outForDelivery, delivered }

enum PanelControlStatus { initialized, isOpened, isClosed }

// default MapCameraStatus is initial, lat 0, lng 0
enum MapCameraStatus {
  initialized,
  showingDeviceLocation,
  showingSourceAndDestinationLocations,
  showRiderLocation,
  showingRiderLocation
}

enum SourceAndDestinationStatus { unselected, selected }

enum ChatStatus { initial, newMessage }

class SendPackageState {
  List<Suggestion> suggestions;
  List ongoingRequests;
  String? pickupLocation;
  String? destinationLocation;
  String? pickupLocationSubAddress;
  String? destinationLocationSubAddress;
  PlaceCoordinate? pickupCoordinate;
  PlaceCoordinate? desinationCoordinate;
  PlaceCoordinate? riderLocation;
  double? distance;
  final DeliveryStatus deliveryStatus;
  PanelControlStatus panelControlStatus;
  ContactInfo? pickupDetails;
  ContactInfo? dropoffDetails;
  String? pickupLocality;
  String? destinationLocality;
  double minDrawerHeight;
  double maxDrawerHeight;
  double? price;
  double parcelWeightKg;
  DeliveryData? deliveryData;
  Map<MarkerId, Marker> markers;
  List<Polyline> polylines;
  List<LatLng> polylineCoordinates;
  SourceAndDestinationStatus sourceAndDestinationStatus;
  MapCameraStatus mapCameraStatus;
  String currency;
  List<Message> chatMessages;
  ChatStatus chatStatus;
  String? message;
  String? lastHistoryId;
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
      this.panelControlStatus = PanelControlStatus.isClosed,
      this.pickupDetails,
      this.dropoffDetails,
      this.pickupLocality,
      this.destinationLocality,
      this.minDrawerHeight = 180,
      this.maxDrawerHeight = 180,
      this.price,
      this.parcelWeightKg = 0,
      this.deliveryData,
      this.markers = const {},
      this.polylines = const [],
      this.polylineCoordinates = const [],
      this.sourceAndDestinationStatus = SourceAndDestinationStatus.unselected,
      this.mapCameraStatus = MapCameraStatus.initialized,
      this.riderLocation,
      this.currency = 'GBP',
      this.chatMessages = const [],
      this.chatStatus = ChatStatus.initial,
      this.message,
      this.lastHistoryId});

  SendPackageState copyWith(
      {List<Suggestion>? suggestions,
      String? pickupLocation,
      String? destinationLocation,
      String? pickupLocationSubAddress,
      String? destinationLocationSubAddress,
      PlaceCoordinate? pickupCoordinate,
      PlaceCoordinate? desinationCoordinate,
      PlaceCoordinate? riderLocation,
      double? distance,
      DeliveryStatus? deliveryStatus,
      PanelControlStatus? panelControlStatus,
      List? ongoingRequests,
      ContactInfo? pickupDetails,
      ContactInfo? dropoffDetails,
      String? pickupLocality,
      String? destinationLocality,
      double? price,
      double? parcelWeightKg,
      DeliveryData? deliveryData,
      Map<MarkerId, Marker>? markers,
      double? minDrawerHeight,
      double? maxDrawerHeight,
      List<Polyline>? polylines,
      List<LatLng>? polylineCoordinates,
      SourceAndDestinationStatus? sourceAndDestinationStatus,
      MapCameraStatus? mapCameraStatus,
      String? currency,
      List<Message>? chatMessages,
      ChatStatus? chatStatus,
      String? message,
      String? lastHistoryId}) {
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
        riderLocation: riderLocation ?? this.riderLocation,
        distance: distance ?? this.distance,
        deliveryStatus: deliveryStatus ?? this.deliveryStatus,
        panelControlStatus: panelControlStatus ?? this.panelControlStatus,
        ongoingRequests: ongoingRequests ?? this.ongoingRequests,
        pickupDetails: pickupDetails ?? this.pickupDetails,
        dropoffDetails: dropoffDetails ?? this.dropoffDetails,
        pickupLocality: pickupLocality ?? this.pickupLocality,
        destinationLocality: destinationLocality ?? this.destinationLocality,
        price: price ?? this.price,
        parcelWeightKg: parcelWeightKg ?? this.parcelWeightKg,
        deliveryData: deliveryData ?? this.deliveryData,
        markers: markers ?? this.markers,
        polylines: polylines ?? this.polylines,
        polylineCoordinates: polylineCoordinates ?? this.polylineCoordinates,
        sourceAndDestinationStatus:
            sourceAndDestinationStatus ?? this.sourceAndDestinationStatus,
        mapCameraStatus: mapCameraStatus ?? this.mapCameraStatus,
        currency: currency ?? this.currency,
        chatMessages: chatMessages ?? this.chatMessages,
        chatStatus: chatStatus ?? this.chatStatus,
        minDrawerHeight: minDrawerHeight ?? this.minDrawerHeight,
        maxDrawerHeight: maxDrawerHeight ?? this.maxDrawerHeight,
        message: message ?? this.message,
        lastHistoryId: lastHistoryId ?? this.lastHistoryId);
  }
}
