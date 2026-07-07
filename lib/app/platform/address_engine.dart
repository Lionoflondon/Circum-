import '../send_package/models/suggestions.m.dart';

class AddressEngine {
  static const canonicalFields = [
    'addressLine1',
    'addressLine2',
    'city',
    'countyState',
    'postcode',
    'country',
    'formattedAddress',
    'placeId',
    'latitude',
    'longitude',
  ];

  static String clean(Object? value) {
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

  static String joinParts(Iterable<Object?> values, {String separator = ', '}) {
    return values
        .map(clean)
        .where((value) => value.isNotEmpty)
        .where((value) => value != ',')
        .toList()
        .join(separator);
  }

  static String firstPart(Iterable<Object?> values) {
    for (final value in values) {
      final cleaned = clean(value);
      if (cleaned.isNotEmpty) return cleaned;
    }
    return '';
  }

  static Map<String, dynamic> normalize({
    Suggestion? suggestion,
    Map<String, dynamic>? components,
    String? manualAddress,
    Object? placeId,
    Object? latitude,
    Object? longitude,
  }) {
    final raw = <String, dynamic>{
      ...?components,
      ...suggestion?.components ?? const <String, dynamic>{},
    };
    final streetNumber = firstPart([
      raw['streetNumber'],
      raw['buildingNumber'],
      raw['premise'],
      raw['subBuildingName'],
    ]);
    final route = firstPart([
      raw['route'],
      raw['street'],
      raw['thoroughfare'],
    ]);
    final line1FromParts = joinParts([streetNumber, route], separator: ' ');
    final manualParts = (manualAddress ?? suggestion?.description ?? '')
        .split(',')
        .map(clean)
        .where((value) => value.isNotEmpty)
        .toList();
    final rawLine1 = firstPart([
      raw['addressLine1'],
      raw['line1'],
      raw['displayAddressLine1'],
    ]);
    final addressLine1 = firstPart([
      rawLine1,
      line1FromParts,
      manualParts.isNotEmpty ? manualParts.first : null,
      suggestion?.mainText,
    ]);
    final addressLine2 = firstPart([
      raw['addressLine2'],
      raw['line2'],
      raw['unit'],
      raw['flat'],
    ]);
    final city = firstPart([
      raw['city'],
      raw['locality'],
      raw['town'],
      raw['postTown'],
      manualParts.length >= 3
          ? manualParts[manualParts.length - 3]
          : manualParts.length >= 2
              ? manualParts[manualParts.length - 2]
              : null,
    ]);
    final countyState = firstPart([
      raw['countyState'],
      raw['county'],
      raw['state'],
      raw['region'],
    ]);
    final postcode = firstPart([
      raw['postcode'],
      raw['postalCode'],
      raw['zip'],
      manualParts.length >= 2 ? manualParts[manualParts.length - 2] : null,
    ]);
    final country = firstPart([
      raw['country'],
      manualParts.isNotEmpty ? manualParts.last : null,
    ]);
    final formattedAddress = joinParts([
      addressLine1,
      addressLine2,
      city,
      countyState,
      postcode,
      country,
    ]);
    final lat =
        toDouble(latitude ?? raw['latitude'] ?? raw['lat'] ?? suggestion?.lat);
    final lng = toDouble(
        longitude ?? raw['longitude'] ?? raw['lng'] ?? suggestion?.lng);

    return {
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'countyState': countyState,
      'postcode': postcode,
      'country': country,
      'formattedAddress': formattedAddress,
      'placeId': firstPart([placeId, raw['placeId'], suggestion?.placeId]),
      'latitude': lat,
      'longitude': lng,
    }..removeWhere((key, value) => value == null || clean(value).isEmpty);
  }

  static bool isValid(Map<String, dynamic> address) {
    return clean(address['addressLine1']).isNotEmpty &&
        clean(address['city']).isNotEmpty &&
        clean(address['postcode']).isNotEmpty &&
        clean(address['country']).isNotEmpty;
  }

  static bool hasRequiredFields({
    Suggestion? suggestion,
    Map<String, dynamic>? components,
    String? manualAddress,
  }) {
    return isValid(
      normalize(
        suggestion: suggestion,
        components: components,
        manualAddress: manualAddress,
      ),
    );
  }

  static Suggestion suggestionFromBackend(Map<String, dynamic> map) {
    final components = map['components'] is Map
        ? Map<String, dynamic>.from(map['components'] as Map)
        : <String, dynamic>{};
    final rawSuggestion = Suggestion(
      placeId: clean(map['locationId']).isEmpty
          ? clean(map['placeId'])
          : clean(map['locationId']),
      description: clean(map['displayAddress'] ?? map['formattedAddress']),
      subText: '',
      mainText: '',
      lat: toDouble(map['lat'] ?? map['latitude']),
      lng: toDouble(map['lng'] ?? map['longitude']),
      components: components,
    );
    return cleanSuggestion(rawSuggestion);
  }

  static Suggestion cleanSuggestion(Suggestion suggestion) {
    final normalized = normalize(
      suggestion: suggestion,
      manualAddress: suggestion.description,
    );
    final description = firstPart([
      normalized['formattedAddress'],
      suggestion.description,
    ]);
    final mainText = firstPart([
      normalized['addressLine1'],
      suggestion.mainText,
    ]);
    final subText = joinParts([
      normalized['city'],
      normalized['countyState'],
      normalized['postcode'],
      normalized['country'],
    ]);
    return Suggestion(
      placeId: firstPart([suggestion.placeId, description]),
      description: description,
      subText: subText.isEmpty ? description : subText,
      mainText: mainText,
      lat: toDouble(normalized['latitude']),
      lng: toDouble(normalized['longitude']),
      components: normalized,
    );
  }

  static String display(Map<String, dynamic>? address, {String fallback = ''}) {
    if (address == null) return clean(fallback);
    return firstPart([
      address['formattedAddress'],
      joinParts([
        address['addressLine1'],
        address['addressLine2'],
        address['city'],
        address['postcode'],
        address['country'],
      ]),
      fallback,
    ]);
  }

  static double? toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(clean(value));
  }
}
