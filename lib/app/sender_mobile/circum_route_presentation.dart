import 'package:flutter/material.dart';

abstract final class CircumRoutePresentation {
  static const base = Color(0xFF2563EB);
  static const energy = Color(0xFF34D399);
  static const glow = Color(0xFF38BDF8);

  static List<T> energySegment<T>(List<T> route, double phase) {
    if (route.length < 2) return const [];
    final lastStart = route.length - 2;
    final start = (phase.clamp(0, 1) * lastStart).floor();
    final window = (route.length / 5).ceil().clamp(2, 12);
    final end = (start + window).clamp(start + 2, route.length);
    return route.sublist(start, end);
  }
}
