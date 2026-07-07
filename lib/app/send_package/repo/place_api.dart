import 'package:cloud_functions/cloud_functions.dart';

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
        .call({'query': query});
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    final results =
        data['results'] is Iterable ? data['results'] as Iterable : const [];
    final suggestions = results
        .map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final components = map['components'] is Map
              ? Map<String, dynamic>.from(map['components'] as Map)
              : <String, dynamic>{};
          final description = _clean(map['displayAddress']);
          final streetNumber = _firstAddressPart([
            components['streetNumber'],
            components['buildingNumber'],
            components['premise'],
          ]);
          final route = _firstAddressPart([
            components['street'],
            components['route'],
            components['thoroughfare'],
          ]);
          final street = _joinAddressParts(
            [streetNumber, route],
            separator: ' ',
          );
          final mainText =
              street.isNotEmpty ? street : description.split(',').first.trim();
          final subText = _joinAddressParts([
            components['locality'],
            components['town'],
            components['city'],
            components['postcode'],
            components['country'],
          ]);
          final suggestion = Suggestion(
            placeId: _clean(map['locationId']).isEmpty
                ? description
                : _clean(map['locationId']),
            description: description,
            mainText: mainText,
            subText: subText.isEmpty ? description : subText,
            lat: _toDouble(map['lat']),
            lng: _toDouble(map['lng']),
            components: components,
          );
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
    throw Exception("Couldn't fetch location details");
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static String _clean(Object? value) {
    final text = '${value ?? ''}'.trim();
    final lower = text.toLowerCase();
    if (text.isEmpty ||
        lower == 'null' ||
        lower == 'undefined' ||
        lower == '[]' ||
        lower == '||') {
      return '';
    }
    return text;
  }

  static String _joinAddressParts(
    Iterable<Object?> values, {
    String separator = ', ',
  }) {
    return values
        .map(_clean)
        .where((value) => value.isNotEmpty)
        .toList()
        .join(separator);
  }

  static String _firstAddressPart(Iterable<Object?> values) {
    for (final value in values) {
      final cleaned = _clean(value);
      if (cleaned.isNotEmpty) return cleaned;
    }
    return '';
  }
}
