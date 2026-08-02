part of 'send_package_bloc.dart';

abstract class SendPackageEvent {
  const SendPackageEvent();
}

class SearchAPlaceEvent extends SendPackageEvent {
  final String query;
  final String lang;

  const SearchAPlaceEvent({required this.query, required this.lang});
}

class SetPickupAddress extends SendPackageEvent {
  String val;
  String pickupLocationSubAddress;
  String placeId;
  String lang;
  SetPickupAddress({
    required this.val,
    required this.pickupLocationSubAddress,
    required this.placeId,
    required this.lang,
  });
}

class SetDeliveryAddress extends SendPackageEvent {
  String val;
  String destinationLocationSubAddress;
  String placeId;
  String lang;
  SetDeliveryAddress({
    required this.val,
    required this.destinationLocationSubAddress,
    required this.placeId,
    required this.lang,
  });
}

class ClearSuggestions extends SendPackageEvent {}

class ResetSenderBookingSession extends SendPackageEvent {
  const ResetSenderBookingSession();
}

class CalculateDistance extends SendPackageEvent {}

class RestoreSenderRoute extends SendPackageEvent {
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String dropoffAddress;
  final double dropoffLat;
  final double dropoffLng;

  const RestoreSenderRoute({
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffAddress,
    required this.dropoffLat,
    required this.dropoffLng,
  });
}

class SendAPackage extends SendPackageEvent {}

class SetDeliveryStatus extends SendPackageEvent {
  final DeliveryStatus deliveryStatus;
  const SetDeliveryStatus({required this.deliveryStatus});
}

class SendDeliveryRequest extends SendPackageEvent {
  final ContactInfo pickupDetails;
  final ContactInfo dropoffDetails;
  const SendDeliveryRequest({
    required this.pickupDetails,
    required this.dropoffDetails,
  });
}

class SetDistance extends SendPackageEvent {
  final double value;
  const SetDistance({required this.value});
}

class SetPrice extends SendPackageEvent {}

class SetParcelWeight extends SendPackageEvent {
  final double weightKg;
  final String? itemDescription;
  const SetParcelWeight({required this.weightKg, this.itemDescription});
}

class ClearIrisParcelState extends SendPackageEvent {
  const ClearIrisParcelState();
}

class RequestCanonicalIrisEstimate extends SendPackageEvent {
  final String itemName;
  final int quantity;
  final String description;
  final String declaredWeightText;
  final bool fragile;
  final bool highValue;

  const RequestCanonicalIrisEstimate({
    required this.itemName,
    this.quantity = 1,
    this.description = '',
    this.declaredWeightText = '',
    this.fragile = false,
    this.highValue = false,
  });
}

class RequestSenderBookingQuote extends SendPackageEvent {
  final String selectedSpeed;
  final bool vanguardProtocolEnabled;
  final String itemName;
  final String description;
  final double weightKg;
  final bool fragile;
  final bool highValue;
  final String selectedVehicle;
  final String irisPhotoAnalysisId;
  final Map<String, dynamic>? businessContext;

  const RequestSenderBookingQuote({
    required this.selectedSpeed,
    required this.vanguardProtocolEnabled,
    required this.itemName,
    required this.description,
    required this.weightKg,
    required this.fragile,
    required this.highValue,
    this.selectedVehicle = '',
    this.irisPhotoAnalysisId = '',
    this.businessContext,
  });
}

class LoadSenderRothBalance extends SendPackageEvent {
  const LoadSenderRothBalance();
}

class StartSenderPaymentSession extends SendPackageEvent {
  final bool rothEnabled;
  final String fallbackMethod;
  final String paymentMethodId;
  final String checkoutMode;
  final String returnUrl;
  final String draftId;
  final String idempotencyKey;
  final Map<String, dynamic> deliveryPayload;

  const StartSenderPaymentSession({
    required this.rothEnabled,
    required this.fallbackMethod,
    this.paymentMethodId = '',
    this.checkoutMode = '',
    this.returnUrl = '',
    this.draftId = '',
    this.idempotencyKey = '',
    this.deliveryPayload = const {},
  });
}

class CreatePaidSenderDelivery extends SendPackageEvent {
  final Map<String, dynamic> bookingPayload;

  const CreatePaidSenderDelivery({required this.bookingPayload});
}

class FinalizeSenderWebCheckout extends SendPackageEvent {
  final String checkoutSessionId;
  final String paymentSessionId;

  const FinalizeSenderWebCheckout({
    required this.checkoutSessionId,
    required this.paymentSessionId,
  });
}

class CheckForPushToken extends SendPackageEvent {}

class DeliveryAccepted extends SendPackageEvent {
  final Map data;
  DeliveryAccepted({required this.data});
}

class DeliveryCompleted extends SendPackageEvent {
  final Map data;
  DeliveryCompleted({required this.data});
}

class SetSourceAndDestinationStatus extends SendPackageEvent {
  final SourceAndDestinationStatus status;
  SetSourceAndDestinationStatus({required this.status});
}

class SetMapCameraStatus extends SendPackageEvent {
  final MapCameraStatus status;
  SetMapCameraStatus({required this.status});
}

class SetRiderLocation extends SendPackageEvent {
  final Map data;
  SetRiderLocation({required this.data});
}

class CheckForActiveRequest extends SendPackageEvent {}

class WatchActiveDelivery extends SendPackageEvent {
  final String requestId;
  const WatchActiveDelivery({required this.requestId});
}

class ActiveDeliverySnapshotChanged extends SendPackageEvent {
  final Map<String, dynamic>? data;
  final String? errorMessage;
  final String? clearedRequestId;
  const ActiveDeliverySnapshotChanged({
    this.data,
    this.errorMessage,
    this.clearedRequestId,
  });
}

class ActiveDeliveryLiveLocationChanged extends SendPackageEvent {
  final Map<String, dynamic>? data;
  const ActiveDeliveryLiveLocationChanged({this.data});
}

class SetPanelControlStatus extends SendPackageEvent {
  final PanelControlStatus status;
  SetPanelControlStatus({required this.status});
}

class SetDrawerHeight extends SendPackageEvent {
  final double minDrawerHeight;
  final double maxDrawerHeight;
  SetDrawerHeight({
    required this.minDrawerHeight,
    required this.maxDrawerHeight,
  });
}

class SetNewMessage extends SendPackageEvent {
  final String value;
  SetNewMessage({required this.value});
}

class IncomingMessage extends SendPackageEvent {
  final dynamic data;

  IncomingMessage({required this.data});
}

class LoadChatMessages extends SendPackageEvent {}

class MessageRider extends SendPackageEvent {
  final String message;
  MessageRider({required this.message});
}

class DeleteCompletedDelivery extends SendPackageEvent {}

class CancelRequest extends SendPackageEvent {}

class BackButtonPressed extends SendPackageEvent {}
