import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

double calculateBearing(LatLng startPoint, LatLng endPoint) {
  final double startLat = toRadians(startPoint.latitude);
  final double startLng = toRadians(startPoint.longitude);
  final double endLat = toRadians(endPoint.latitude);
  final double endLng = toRadians(endPoint.longitude);

  final double deltaLng = endLng - startLng;

  final double y = math.sin(deltaLng) * math.cos(endLat);
  final double x = math.cos(startLat) * math.sin(endLat) -
      math.sin(startLat) * math.cos(endLat) * math.cos(deltaLng);

  final double bearing = math.atan2(y, x);

  return (toDegrees(bearing) + 360) % 360;
}

double toRadians(double degrees) {
  return degrees * (math.pi / 180.0);
}

double toDegrees(double radians) {
  return radians * (180.0 / math.pi);
}
