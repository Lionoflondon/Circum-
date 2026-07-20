import 'package:cloud_firestore/cloud_firestore.dart';

import 'place_coordinates.m.dart';

typedef RestoredDeliveryCoordinates = ({
  PlaceCoordinate pickup,
  PlaceCoordinate dropoff,
});

RestoredDeliveryCoordinates restoreDeliveryCoordinates(
  Map<String, dynamic> delivery,
) {
  return (
    pickup: _coordinateFor(delivery, 'pickupDetails'),
    dropoff: _coordinateFor(delivery, 'dropoffDetails'),
  );
}

PlaceCoordinate _coordinateFor(
  Map<String, dynamic> delivery,
  String detailsKey,
) {
  final details = delivery[detailsKey];
  final position = details is Map ? details['position'] : null;
  final geopoint = position is Map
      ? position['geopoint'] ?? position['geoPoint'] ?? position['location']
      : null;

  if (geopoint is GeoPoint) {
    return PlaceCoordinate(
      lat: geopoint.latitude,
      lng: geopoint.longitude,
    );
  }

  if (geopoint is Map) {
    final latitude = geopoint['latitude'] ?? geopoint['lat'];
    final longitude = geopoint['longitude'] ?? geopoint['lng'];
    if (latitude is num && longitude is num) {
      return PlaceCoordinate(
        lat: latitude.toDouble(),
        lng: longitude.toDouble(),
      );
    }
  }

  throw StateError('$detailsKey does not contain valid coordinates.');
}
