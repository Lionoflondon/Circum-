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
  const SendDeliveryRequest(
      {required this.pickupDetails, required this.dropoffDetails});
}

class SetDistance extends SendPackageEvent {
  final double value;
  const SetDistance({required this.value});
}

class SetPrice extends SendPackageEvent {}

class CheckForPushToken extends SendPackageEvent {}

class DeliveryAccepted extends SendPackageEvent {
  final Map data;
  DeliveryAccepted({required this.data});
}

class SetSourceAndDestinationStatus extends SendPackageEvent {
  final SourceAndDestinationStatus status;
  SetSourceAndDestinationStatus({required this.status});
}

class SetMapCameraStatus extends SendPackageEvent {
  final MapCameraStatus status;
  SetMapCameraStatus({required this.status});
}
