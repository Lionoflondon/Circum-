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
    final suggestion = _suggestionCache[placeId];
    if (suggestion?.lat != null && suggestion?.lng != null) {
      return PlaceCoordinate(lat: suggestion!.lat!, lng: suggestion.lng!);
    }
    final response = await FirebaseFunctions.instance
        .httpsCallable('resolveUkAddressPlace')
        .call({
      'placeId': placeId,
      if (suggestion?.description.trim().isNotEmpty ?? false)
        'sourceInput': suggestion!.description,
      'sessionToken': '$sessionToken',
    }).timeout(const Duration(seconds: 8));
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
      return PlaceCoordinate(lat: resolved.lat!, lng: resolved.lng!);
    }
    throw Exception("Couldn't fetch location details");
  }

  Future<Suggestion> resolveTypedAddress(String input, String lang) async {
    final query = input.trim();
    if (query.length < 6) {
      throw Exception('Enter a fuller address before continuing');
    }
    final suggestions = await fetchSuggestions(query, lang);
    final candidate = _bestTypedResolutionCandidate(query, suggestions);
    if (candidate == null) {
      throw Exception("Couldn't resolve a unique address");
    }
    return _resolveSuggestion(candidate.placeId, lang, sourceInput: query);
  }

  Future<Suggestion> resolveSuggestion(String placeId, String lang) async {
    return _resolveSuggestion(placeId, lang);
  }

  Future<Suggestion> _resolveSuggestion(
    String placeId,
    String lang, {
    String? sourceInput,
  }) async {
    final response = await FirebaseFunctions.instance
        .httpsCallable('resolveUkAddressPlace')
        .call({
      'placeId': placeId,
      if ((sourceInput?.trim().isNotEmpty ?? false))
        'sourceInput': sourceInput!.trim()
      else if ((_suggestionCache[placeId]?.description.trim().isNotEmpty ??
          false))
        'sourceInput': _suggestionCache[placeId]!.description,
      'sessionToken': '$sessionToken',
    }).timeout(const Duration(seconds: 8));
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    final resolved = _preserveCachedUnitMetadata(
      AddressEngine.suggestionFromBackend(data),
      _suggestionCache[placeId],
    );
    _suggestionCache[resolved.placeId] = resolved;
    _suggestionCache[placeId] = resolved;
    if (resolved.lat == null || resolved.lng == null) {
      throw Exception("Couldn't resolve address details");
    }
    return resolved;
  }

  Suggestion? _bestTypedResolutionCandidate(
    String input,
    List<Suggestion> suggestions,
  ) {
    if (suggestions.isEmpty) return null;
    final normalizedInput = _normalizeAddressText(input);
    final postcode = _extractUkPostcode(normalizedInput);
    final buildingNumber = _extractBuildingNumber(normalizedInput);

    final scored = suggestions
        .map(
          (suggestion) => (
            suggestion: suggestion,
            score: _typedResolutionScore(
              normalizedInput,
              postcode,
              buildingNumber,
              suggestion,
            ),
          ),
        )
        .where((item) => item.score >= 3)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (scored.isEmpty) return null;
    if (scored.length == 1) return scored.first.suggestion;

    final best = scored.first;
    final second = scored[1];
    if (best.score >= second.score + 2) return best.suggestion;
    return null;
  }

  int _typedResolutionScore(
    String normalizedInput,
    String postcode,
    String buildingNumber,
    Suggestion suggestion,
  ) {
    final description = _normalizeAddressText(suggestion.description);
    final mainText = _normalizeAddressText(suggestion.mainText);
    final combined = '$description $mainText';
    var score = 0;
    if (description == normalizedInput || mainText == normalizedInput) {
      score += 10;
    }
    if (description.startsWith(normalizedInput) ||
        normalizedInput.startsWith(description)) {
      score += 4;
    }
    if (postcode.isNotEmpty && combined.contains(postcode)) score += 4;
    if (buildingNumber.isNotEmpty &&
        RegExp(
          '(^| )${RegExp.escape(buildingNumber)}( |\\b)',
        ).hasMatch(combined)) {
      score += 3;
    }
    for (final token in normalizedInput.split(' ')) {
      if (token.length >= 4 && combined.contains(token)) score += 1;
    }
    return score;
  }

  String _normalizeAddressText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[,]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String _extractUkPostcode(String value) {
    return RegExp(
          r'\b[a-z]{1,2}\d[a-z\d]?\s*\d[a-z]{2}\b',
        ).firstMatch(value)?.group(0)?.replaceAll(RegExp(r'\s+'), ' ') ??
        '';
  }

  String _extractBuildingNumber(String value) {
    return RegExp(r'\b\d+[a-z]?\b').firstMatch(value)?.group(0) ?? '';
  }

  Suggestion _preserveCachedUnitMetadata(
    Suggestion resolved,
    Suggestion? cached,
  ) {
    if (cached == null) return resolved;
    final cachedApartment = AddressEngine.clean(cached.components['apartment']);
    if (cachedApartment.isEmpty) return resolved;

    final cachedBuilding = AddressEngine.clean(
      cached.components['buildingNumber'],
    );
    final resolvedBuilding = AddressEngine.clean(
      resolved.components['buildingNumber'],
    );
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
