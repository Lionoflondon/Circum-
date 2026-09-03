import 'dart:async';

class RouteCoordinate {
  const RouteCoordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class RouteRequestCoordinator<T> {
  RouteRequestCoordinator({
    required this.load,
    this.ttl = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<T> Function(RouteCoordinate origin, RouteCoordinate destination)
      load;
  final Duration ttl;
  final DateTime Function() _clock;
  final Map<String, _RouteCacheEntry<T>> _cache = {};
  final Map<String, Future<T>> _inFlight = {};

  Future<T> resolve(RouteCoordinate origin, RouteCoordinate destination) {
    final key = _key(origin, destination);
    final cached = _cache[key];
    final now = _clock();
    if (cached != null && now.difference(cached.createdAt) <= ttl) {
      return Future<T>.value(cached.value);
    }
    _cache.remove(key);
    return _inFlight.putIfAbsent(key, () async {
      try {
        final value = await load(origin, destination);
        _cache[key] = _RouteCacheEntry(value, _clock());
        return value;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  String _key(RouteCoordinate origin, RouteCoordinate destination) =>
      '${origin.latitude.toStringAsFixed(5)},${origin.longitude.toStringAsFixed(5)}:'
      '${destination.latitude.toStringAsFixed(5)},${destination.longitude.toStringAsFixed(5)}';
}

class _RouteCacheEntry<T> {
  const _RouteCacheEntry(this.value, this.createdAt);

  final T value;
  final DateTime createdAt;
}
