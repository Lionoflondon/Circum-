import 'package:cloud_functions/cloud_functions.dart';

import '../../platform/address_engine.dart';
import '../models/place_coordinates.m.dart';
import '../models/suggestions.m.dart';
// import 'package:http/http.dart';

class PlaceApiProvider {
  PlaceApiProvider(this.sessionToken);

  final Object sessionToken;
  static final Map<String, Suggestion> _suggestionCache = {};

  Future<List<Suggestion>> fetchSuggestions(String input, String lang) async {
    final query = input.trim();
    if (query.length < 3) return [];
    final response = await FirebaseFunctions.instance
        .httpsCallable('searchFreeUkAddresses')
        .call({'query': query, 'sessionToken': '$sessionToken'}).timeout(
            const Duration(seconds: 8));
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
          return suggestion;
        })
        .where((item) => item.description.isNotEmpty)
        .toList();
    return suggestions;
  }

  Future<PlaceCoordinate> fetchPlaceDetails(String placeId, String lang) async {
    final resolved = await fetchResolvedPlace(placeId, lang);
    return PlaceCoordinate(lat: resolved.lat!, lng: resolved.lng!);
  }

  Future<Suggestion> fetchResolvedPlace(String placeId, String lang) async {
    final suggestion = _suggestionCache[placeId];
    if (suggestion?.lat != null && suggestion?.lng != null) {
      return suggestion!;
    }
    final response = await FirebaseFunctions.instance
        .httpsCallable('resolveUkAddressPlace')
        .call({'placeId': placeId, 'sessionToken': '$sessionToken'}).timeout(
            const Duration(seconds: 8));
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    final resolved = _preserveCachedUnitMetadata(
      AddressEngine.suggestionFromBackend(data),
      suggestion,
    );
    _suggestionCache[resolved.placeId] = resolved;
    _suggestionCache[placeId] = resolved;
    if (resolved.lat != null && resolved.lng != null) {
      return resolved;
    }
    throw Exception("Couldn't fetch location details");
  }

  Suggestion _preserveCachedUnitMetadata(
    Suggestion resolved,
    Suggestion? cached,
  ) {
    if (cached == null) return resolved;
    final cachedApartment = AddressEngine.clean(cached.components['apartment']);
    if (cachedApartment.isEmpty) return resolved;

    final cachedBuilding =
        AddressEngine.clean(cached.components['buildingNumber']);
    final resolvedBuilding =
        AddressEngine.clean(resolved.components['buildingNumber']);
    if (cachedBuilding.isNotEmpty &&
        resolvedBuilding.isNotEmpty &&
        cachedBuilding.toLowerCase() != resolvedBuilding.toLowerCase()) {
      return resolved;
    }

    final mergedComponents = <String, dynamic>{
      ...cached.components,
      ...resolved.components,
      'apartment': cachedApartment,
    };
    final merged = Suggestion(
      placeId: resolved.placeId,
      description: resolved.description,
      mainText: resolved.mainText,
      subText: resolved.subText,
      lat: resolved.lat,
      lng: resolved.lng,
      components: mergedComponents,
    );
    return AddressEngine.cleanSuggestion(merged);
  }
}
