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

enum SenderTrackingStage {
  findingRider,
  riderAssigned,
  riderEnRouteToPickup,
  riderArrivedAtPickup,
  pickupComplete,
  inTransit,
  riderArrivingAtDropoff,
  delivered,
  cancelled,
  issue,
}

class SenderTrackingCopy {
  final String title;
  final String body;

  const SenderTrackingCopy(this.title, this.body);
}

const Map<SenderTrackingStage, SenderTrackingCopy> senderTrackingCopy = {
  SenderTrackingStage.findingRider: SenderTrackingCopy(
    'Finding a rider',
    'Iris is checking nearby riders for this delivery.',
  ),
  SenderTrackingStage.riderAssigned: SenderTrackingCopy(
    'Rider assigned',
    'CIRCUM has assigned a rider to this delivery.',
  ),
  SenderTrackingStage.riderEnRouteToPickup: SenderTrackingCopy(
    'Travelling to pickup',
    'Your rider is heading to the pickup location.',
  ),
  SenderTrackingStage.riderArrivedAtPickup: SenderTrackingCopy(
    'Arrived at pickup',
    'Your rider has arrived and is waiting for collection.',
  ),
  SenderTrackingStage.pickupComplete: SenderTrackingCopy(
    'Pickup verified',
    'Collection has been verified and the parcel is with your rider.',
  ),
  SenderTrackingStage.inTransit: SenderTrackingCopy(
    'In transit',
    'Your rider is travelling to the drop-off location.',
  ),
  SenderTrackingStage.riderArrivingAtDropoff: SenderTrackingCopy(
    'Arrived at drop-off',
    'Your rider is at the destination and ready for handover.',
  ),
  SenderTrackingStage.delivered: SenderTrackingCopy(
    'Delivered',
    'Proof of delivery is saved in your Circum history.',
  ),
  SenderTrackingStage.cancelled: SenderTrackingCopy(
    'Closed',
    'This delivery is no longer active.',
  ),
  SenderTrackingStage.issue: SenderTrackingCopy(
    'Needs attention',
    'Circum is reviewing this delivery.',
  ),
};

String _normalizeBackendStatus(Object? value) {
  return '${value ?? ''}'
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[-\s]+'), '_');
}

String backendStatusFromDelivery(Map<String, dynamic> data) {
  return _normalizeBackendStatus(data['deliveryStage'] ??
      data['deliveryStatus'] ??
      data['trackingStatus'] ??
      data['status'] ??
      'requested');
}

SenderTrackingStage senderTrackingStageForBackendStatus(String status) {
  switch (_normalizeBackendStatus(status)) {
    case '':
    case 'requested':
    case 'pending':
    case 'unmatched':
    case 'finding_rider':
    case 'awaiting_rider':
    case 'broadcast':
    case 'broadcasted':
      return SenderTrackingStage.findingRider;
    case 'accepted':
    case 'rider_assigned':
      return SenderTrackingStage.riderAssigned;
    case 'navigating_to_pickup':
    case 'en_route_to_pickup':
      return SenderTrackingStage.riderEnRouteToPickup;
    case 'arrived_at_pickup':
    case 'waiting':
      return SenderTrackingStage.riderArrivedAtPickup;
    case 'pickup_verification':
    case 'pickup_verified':
    case 'collected':
      return SenderTrackingStage.pickupComplete;
    case 'out_for_delivery':
    case 'outfordelivery':
    case 'navigating_to_dropoff':
      return SenderTrackingStage.inTransit;
    case 'arrived_at_dropoff':
    case 'pin_required':
    case 'handover_pending':
      return SenderTrackingStage.riderArrivingAtDropoff;
    case 'delivered':
    case 'completed':
    case 'delivery_completed':
      return SenderTrackingStage.delivered;
    case 'cancelled':
    case 'canceled':
    case 'cancelled_verified_discrepancy':
    case 'sender_no_show_pickup':
      return SenderTrackingStage.cancelled;
    case 'issue':
    case 'issue_reported':
    case 'failed':
    case 'failed_delivery':
    case 'error':
      return SenderTrackingStage.issue;
    default:
      return SenderTrackingStage.inTransit;
  }
}

SenderTrackingStage senderTrackingStageFromDelivery(Map<String, dynamic> data) {
  return senderTrackingStageForBackendStatus(backendStatusFromDelivery(data));
}

String? senderVisiblePinFromDelivery(Map<String, dynamic> data) {
  final stage = senderTrackingStageFromDelivery(data);
  if (stage != SenderTrackingStage.riderArrivingAtDropoff) return null;
  for (final key in const [
    'senderVisiblePin',
    'senderHandoverPin',
    'senderPin',
  ]) {
    final value = '${data[key] ?? ''}'.trim();
    if (RegExp(r'^\d{4,8}$').hasMatch(value)) return value;
  }
  return null;
}

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
  SenderTrackingStage trackingStage;
  Map<String, dynamic>? activeDeliveryData;
  String? senderVisiblePin;
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
      this.lastHistoryId,
      this.trackingStage = SenderTrackingStage.findingRider,
      this.activeDeliveryData,
      this.senderVisiblePin});

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
      String? lastHistoryId,
      SenderTrackingStage? trackingStage,
      Map<String, dynamic>? activeDeliveryData,
      String? senderVisiblePin,
      bool clearActiveDeliveryData = false,
      bool clearSenderVisiblePin = false}) {
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
        lastHistoryId: lastHistoryId ?? this.lastHistoryId,
        trackingStage: trackingStage ?? this.trackingStage,
        activeDeliveryData: clearActiveDeliveryData
            ? null
            : activeDeliveryData ?? this.activeDeliveryData,
        senderVisiblePin: clearSenderVisiblePin
            ? null
            : senderVisiblePin ?? this.senderVisiblePin);
  }
}
