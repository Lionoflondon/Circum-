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
