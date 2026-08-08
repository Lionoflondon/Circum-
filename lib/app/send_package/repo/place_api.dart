import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../../platform/address_engine.dart';
import '../models/place_coordinates.m.dart';
import '../models/suggestions.m.dart';
// import 'package:http/http.dart';

class PlaceApiProvider {
  PlaceApiProvider(Object sessionToken) : sessionToken = _token(sessionToken);

  final String sessionToken;
  static final Map<String, Suggestion> _suggestionCache = {};
  static final Map<String, String> _sessionTokenByPlaceId = {};

  static String _token(Object value) {
    final text = '$value'.trim();
    return text.isEmpty || text.startsWith('Instance of ') ? Uuid().v4() : text;
  }

  Future<List<Suggestion>> fetchSuggestions(String input, String lang) async {
    final query = input.trim();
    if (query.length < 3) return [];
    final response = await FirebaseFunctions.instance
        .httpsCallable('searchFreeUkAddresses')
        .call({
      'query': query,
      'sessionToken': sessionToken,
    }).timeout(const Duration(seconds: 8));
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    final results =
        data['results'] is Iterable ? data['results'] as Iterable : const [];
    final suggestions = results
        .map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final suggestion = AddressEngine.suggestionFromBackend(map);
          _suggestionCache[suggestion.placeId] = suggestion;
          if (suggestion.placeId.trim().isNotEmpty) {
            _sessionTokenByPlaceId[suggestion.placeId] = sessionToken;
          }
          return suggestion;
        })
        .where((item) => item.description.isNotEmpty)
        .toList();
    return suggestions;
  }

  Future<PlaceCoordinate> fetchPlaceDetails(String placeId, String lang) async {
    final suggestion = _suggestionCache[placeId];
    if (suggestion?.lat != null && suggestion?.lng != null) {
      return PlaceCoordinate(lat: suggestion!.lat!, lng: suggestion.lng!);
    }
    final response = await FirebaseFunctions.instance
        .httpsCallable('resolveUkAddressPlace')
        .call({
      'placeId': placeId,
      'sessionToken': _sessionTokenByPlaceId[placeId] ?? sessionToken,
    }).timeout(const Duration(seconds: 8));
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    final resolved = AddressEngine.suggestionFromBackend(data);
    _suggestionCache[resolved.placeId] = resolved;
    _suggestionCache[placeId] = resolved;
    _sessionTokenByPlaceId.remove(placeId);
    if (resolved.lat != null && resolved.lng != null) {
      return PlaceCoordinate(lat: resolved.lat!, lng: resolved.lng!);
    }
    throw Exception("Couldn't fetch location details");
  }
}
