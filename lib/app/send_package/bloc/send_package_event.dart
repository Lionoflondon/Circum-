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
  SetPickupAddress(
      {required this.val,
      required this.pickupLocationSubAddress,
      required this.placeId,
      required this.lang});
}

class SetDeliveryAddress extends SendPackageEvent {
  String val;
  String destinationLocationSubAddress;
  String placeId;
  String lang;
  SetDeliveryAddress(
      {required this.val,
      required this.destinationLocationSubAddress,
      required this.placeId,
      required this.lang});
}

class ClearSuggestions extends SendPackageEvent {}

class CalculateDistance extends SendPackageEvent {}

class SendAPackage extends SendPackageEvent {}

class SetDeliveryStatus extends SendPackageEvent {
  final DeliveryStatus deliveryStatus;
  const SetDeliveryStatus({required this.deliveryStatus});
}

class SendDeliveryRequest extends SendPackageEvent {
  final ContactInfo pickupDetails;
  final ContactInfo dropoffDetails;
  final String? paymentIntentId;
  final String? quoteId;
  final String? paymentSessionId;
  final String? requestId;
  const SendDeliveryRequest(
      {required this.pickupDetails,
      required this.dropoffDetails,
      this.paymentIntentId,
      this.quoteId,
      this.paymentSessionId,
      this.requestId});
}

class SetDistance extends SendPackageEvent {
  final double value;
  const SetDistance({required this.value});
}

class SetPrice extends SendPackageEvent {}

class SetParcelWeight extends SendPackageEvent {
  final double weightKg;
  const SetParcelWeight({required this.weightKg});
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

class SetPanelControlStatus extends SendPackageEvent {
  final PanelControlStatus status;
  SetPanelControlStatus({required this.status});
}

class SetDrawerHeight extends SendPackageEvent {
  final double minDrawerHeight;
  final double maxDrawerHeight;
  SetDrawerHeight(
      {required this.minDrawerHeight, required this.maxDrawerHeight});
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

class ActiveDeliverySnapshotUpdated extends SendPackageEvent {
  final Map<String, dynamic>? data;
  const ActiveDeliverySnapshotUpdated({required this.data});
}
