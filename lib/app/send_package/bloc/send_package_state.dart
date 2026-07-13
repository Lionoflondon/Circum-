part of 'send_package_bloc.dart';

enum DeliveryStatus {
  inital,
  addressesSelected,
  deliveryConfirmed,
  deliveryOnGoing,
  deliveryCompleted,
  reconnectingWithRider,
}

enum ParcelStatus { requested, accepted, outForDelivery, delivered }

enum PanelControlStatus { initialized, isOpened, isClosed }

// default MapCameraStatus is initial, lat 0, lng 0
enum MapCameraStatus {
  initialized,
  showingDeviceLocation,
  showingSourceAndDestinationLocations,
  showRiderLocation,
  showingRiderLocation,
}

enum SourceAndDestinationStatus { unselected, selected }

enum ChatStatus { initial, newMessage }

class SendPackageState {
  List<Suggestion> suggestions;
  final bool isAddressSearching;
  final String addressSearchError;
  List ongoingRequests;
  String? pickupLocation;
  String? destinationLocation;
  String? pickupLocationSubAddress;
  String? destinationLocationSubAddress;
  PlaceCoordinate? pickupCoordinate;
  PlaceCoordinate? desinationCoordinate;
  PlaceCoordinate? riderLocation;
  final DateTime? riderLiveLocationUpdatedAt;
  final double? riderLiveLocationHeading;
  double? distance;
  final DeliveryStatus deliveryStatus;
  final String deliveryRequestStatus;
  final Map<String, dynamic> activeDeliveryData;
  final bool collectionPinVerified;
  final bool deliveryPinVerified;
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
  final IrisWeightLookupResult? irisResult;
  final CanonicalIrisResult? canonicalIrisResult;
  final String? itemDescription;
  final bool isIrisResolving;
  final String irisErrorMessage;
  final bool isSenderQuoteLoading;
  final String senderQuoteError;
  final String? senderQuoteId;
  final double? senderQuoteTotal;
  final String? senderQuoteSpeed;
  final List<Map<String, dynamic>> senderQuoteLineItems;
  final bool isSenderRothLoading;
  final String senderRothError;
  final double? senderRothBalance;
  final bool isSenderPaymentLoading;
  final String senderPaymentError;
  final String? senderPaymentSessionId;
  final String? senderPaymentStatus;
  final String? senderPaymentClientSecret;
  final bool isSenderDeliveryCreating;
  final String senderDeliveryError;
  final String? senderCreatedRequestId;
  SendPackageState({
    this.suggestions = const [],
    this.isAddressSearching = false,
    this.addressSearchError = '',
    this.ongoingRequests = const [],
    this.pickupLocation,
    this.destinationLocation,
    this.pickupLocationSubAddress,
    this.destinationLocationSubAddress,
    this.pickupCoordinate,
    this.desinationCoordinate,
    this.distance,
    this.deliveryStatus = DeliveryStatus.inital,
    this.deliveryRequestStatus = '',
    this.activeDeliveryData = const {},
    this.collectionPinVerified = false,
    this.deliveryPinVerified = false,
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
    this.riderLiveLocationUpdatedAt,
    this.riderLiveLocationHeading,
    this.currency = 'GBP',
    this.chatMessages = const [],
    this.chatStatus = ChatStatus.initial,
    this.message,
    this.lastHistoryId,
    this.irisResult,
    this.canonicalIrisResult,
    this.itemDescription,
    this.isIrisResolving = false,
    this.irisErrorMessage = '',
    this.isSenderQuoteLoading = false,
    this.senderQuoteError = '',
    this.senderQuoteId,
    this.senderQuoteTotal,
    this.senderQuoteSpeed,
    this.senderQuoteLineItems = const [],
    this.isSenderRothLoading = false,
    this.senderRothError = '',
    this.senderRothBalance,
    this.isSenderPaymentLoading = false,
    this.senderPaymentError = '',
    this.senderPaymentSessionId,
    this.senderPaymentStatus,
    this.senderPaymentClientSecret,
    this.isSenderDeliveryCreating = false,
    this.senderDeliveryError = '',
    this.senderCreatedRequestId,
  });

  SendPackageState copyWith({
    List<Suggestion>? suggestions,
    bool? isAddressSearching,
    String? addressSearchError,
    String? pickupLocation,
    String? destinationLocation,
    String? pickupLocationSubAddress,
    String? destinationLocationSubAddress,
    PlaceCoordinate? pickupCoordinate,
    PlaceCoordinate? desinationCoordinate,
    PlaceCoordinate? riderLocation,
    DateTime? riderLiveLocationUpdatedAt,
    double? riderLiveLocationHeading,
    double? distance,
    DeliveryStatus? deliveryStatus,
    String? deliveryRequestStatus,
    Map<String, dynamic>? activeDeliveryData,
    bool? collectionPinVerified,
    bool? deliveryPinVerified,
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
    IrisWeightLookupResult? irisResult,
    CanonicalIrisResult? canonicalIrisResult,
    String? itemDescription,
    bool? isIrisResolving,
    String? irisErrorMessage,
    bool? isSenderQuoteLoading,
    String? senderQuoteError,
    String? senderQuoteId,
    double? senderQuoteTotal,
    String? senderQuoteSpeed,
    List<Map<String, dynamic>>? senderQuoteLineItems,
    bool? isSenderRothLoading,
    String? senderRothError,
    double? senderRothBalance,
    bool? isSenderPaymentLoading,
    String? senderPaymentError,
    String? senderPaymentSessionId,
    String? senderPaymentStatus,
    String? senderPaymentClientSecret,
    bool? isSenderDeliveryCreating,
    String? senderDeliveryError,
    String? senderCreatedRequestId,
  }) {
    return SendPackageState(
      suggestions: suggestions ?? this.suggestions,
      isAddressSearching: isAddressSearching ?? this.isAddressSearching,
      addressSearchError: addressSearchError ?? this.addressSearchError,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      destinationLocation: destinationLocation ?? this.destinationLocation,
      pickupLocationSubAddress:
          pickupLocationSubAddress ?? this.pickupLocationSubAddress,
      destinationLocationSubAddress:
          destinationLocationSubAddress ?? this.destinationLocationSubAddress,
      pickupCoordinate: pickupCoordinate ?? this.pickupCoordinate,
      desinationCoordinate: desinationCoordinate ?? this.desinationCoordinate,
      riderLocation: riderLocation ?? this.riderLocation,
      riderLiveLocationUpdatedAt:
          riderLiveLocationUpdatedAt ?? this.riderLiveLocationUpdatedAt,
      riderLiveLocationHeading:
          riderLiveLocationHeading ?? this.riderLiveLocationHeading,
      distance: distance ?? this.distance,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      deliveryRequestStatus:
          deliveryRequestStatus ?? this.deliveryRequestStatus,
      activeDeliveryData: activeDeliveryData ?? this.activeDeliveryData,
      collectionPinVerified:
          collectionPinVerified ?? this.collectionPinVerified,
      deliveryPinVerified: deliveryPinVerified ?? this.deliveryPinVerified,
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
      irisResult: irisResult ?? this.irisResult,
      canonicalIrisResult: canonicalIrisResult ?? this.canonicalIrisResult,
      itemDescription: itemDescription ?? this.itemDescription,
      isIrisResolving: isIrisResolving ?? this.isIrisResolving,
      irisErrorMessage: irisErrorMessage ?? this.irisErrorMessage,
      isSenderQuoteLoading: isSenderQuoteLoading ?? this.isSenderQuoteLoading,
      senderQuoteError: senderQuoteError ?? this.senderQuoteError,
      senderQuoteId: senderQuoteId ?? this.senderQuoteId,
      senderQuoteTotal: senderQuoteTotal ?? this.senderQuoteTotal,
      senderQuoteSpeed: senderQuoteSpeed ?? this.senderQuoteSpeed,
      senderQuoteLineItems: senderQuoteLineItems ?? this.senderQuoteLineItems,
      isSenderRothLoading: isSenderRothLoading ?? this.isSenderRothLoading,
      senderRothError: senderRothError ?? this.senderRothError,
      senderRothBalance: senderRothBalance ?? this.senderRothBalance,
      isSenderPaymentLoading:
          isSenderPaymentLoading ?? this.isSenderPaymentLoading,
      senderPaymentError: senderPaymentError ?? this.senderPaymentError,
      senderPaymentSessionId:
          senderPaymentSessionId ?? this.senderPaymentSessionId,
      senderPaymentStatus: senderPaymentStatus ?? this.senderPaymentStatus,
      senderPaymentClientSecret:
          senderPaymentClientSecret ?? this.senderPaymentClientSecret,
      isSenderDeliveryCreating:
          isSenderDeliveryCreating ?? this.isSenderDeliveryCreating,
      senderDeliveryError: senderDeliveryError ?? this.senderDeliveryError,
      senderCreatedRequestId:
          senderCreatedRequestId ?? this.senderCreatedRequestId,
    );
  }
}
