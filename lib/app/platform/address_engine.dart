import '../send_package/models/suggestions.m.dart';

class AddressEngine {
  static final RegExp _ukPostcodePattern = RegExp(
    r'\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b',
    caseSensitive: false,
  );

  static const canonicalFields = [
    'addressId',
    'formattedAddress',
    'addressLine1',
    'addressLine2',
    'buildingName',
    'apartment',
    'floor',
    'entranceInstructions',
    'city',
    'county',
    'postcode',
    'country',
    'placeId',
    'latitude',
    'longitude',
    'verified',
    'source',
    'createdAt',
    'updatedAt',
  ];

  static const compatibilityFields = ['countyState', 'lat', 'lng'];

  static const allSerializableFields = [
    ...canonicalFields,
    ...compatibilityFields,
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

  static String? extractUkPostcode(Object? value) {
    final match = _ukPostcodePattern.firstMatch(clean(value));
    final compact =
        match?.group(0).toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (compact == null || compact.isEmpty) return null;
    if (compact.length <= 3) return compact;
    return '${compact.substring(0, compact.length - 3)} '
        '${compact.substring(compact.length - 3)}';
  }

  static String lookupInput(String value) {
    return display(normalize(manualAddress: value), fallback: value);
  }

  static String normalizeUkPostcodes(String value) => value.replaceAllMapped(
        _ukPostcodePattern,
        (match) => extractUkPostcode(match.group(0))!,
      );

  static String _withoutUkPostcode(Object? value) {
    return clean(value)
        .replaceAll(_ukPostcodePattern, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[,\s]+|[,\s]+$'), '')
        .trim();
  }

  static String _matchKey(Object? value) {
    return clean(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static bool _sameAddressPart(Object? left, Object? right) {
    final a = _matchKey(left);
    final b = _matchKey(right);
    return a.isNotEmpty && a == b;
  }

  static bool _isCountryPart(Object? value) {
    final key = _matchKey(value);
    return key == 'uk' ||
        key == 'gb' ||
        key == 'great britain' ||
        key == 'united kingdom' ||
        key == 'england' ||
        key == 'scotland' ||
        key == 'wales' ||
        key == 'northern ireland';
  }

  static List<String> _locationPartsAfterLine1(
    List<String> manualParts,
    String addressLine1,
  ) {
    final parts = manualParts.toList(growable: true);
    while (parts.length > 1 && _sameAddressPart(parts.first, addressLine1)) {
      parts.removeAt(0);
    }
    return parts;
  }

  static String _cityFromManualParts(List<String> parts, String addressLine1) {
    for (final part in parts.reversed) {
      if (_sameAddressPart(part, addressLine1) || _isCountryPart(part)) {
        continue;
      }
      final withoutPostcode = _withoutUkPostcode(part);
      if (withoutPostcode.isNotEmpty && !_isCountryPart(withoutPostcode)) {
        return withoutPostcode;
      }
    }
    return '';
  }

  static String _countryFromManualParts(List<String> parts) {
    for (final part in parts.reversed) {
      if (_isCountryPart(part)) return clean(part);
    }
    return '';
  }

  static String joinDistinctParts(Iterable<Object?> values) {
    final parts = <String>[];
    for (final value in values) {
      final cleaned = clean(value);
      if (cleaned.isEmpty || cleaned == ',') continue;
      final compact = cleaned.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      if (extractUkPostcode(cleaned) == normalizeUkPostcodes(cleaned) &&
          parts.any((part) {
            final postcode = extractUkPostcode(part);
            return postcode?.toLowerCase().replaceAll(' ', '') == compact;
          })) {
        continue;
      }
      if (parts.any((part) => _sameAddressPart(part, cleaned))) continue;
      parts.add(cleaned);
    }
    return parts.join(', ');
  }

  static Map<String, dynamic> normalize({
    Suggestion? suggestion,
    Map<String, dynamic>? components,
    String? manualAddress,
    Object? addressId,
    Object? placeId,
    Object? latitude,
    Object? longitude,
    Object? verified,
    Object? source,
    Object? createdAt,
    Object? updatedAt,
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
    final route = firstPart([raw['route'], raw['street'], raw['thoroughfare']]);
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
    final buildingName = firstPart([
      raw['buildingName'],
      raw['building'],
      raw['premiseName'],
      raw['premisesName'],
    ]);
    final apartment = firstPart([
      raw['apartment'],
      raw['flat'],
      raw['unit'],
      raw['suite'],
      raw['subpremise'],
    ]);
    final floor = firstPart([raw['floor'], raw['level']]);
    final entranceInstructions = firstPart([
      raw['entranceInstructions'],
      raw['deliveryInstructions'],
      raw['accessInstructions'],
      raw['instructions'],
    ]);
    final addressLine1 = firstPart([
      rawLine1,
      line1FromParts,
      manualParts.isNotEmpty ? manualParts.first : null,
      suggestion?.mainText,
    ]);
    final locationParts = _locationPartsAfterLine1(manualParts, addressLine1);
    final addressLine2 = firstPart([
      raw['addressLine2'],
      raw['line2'],
      buildingName,
      apartment,
    ]);
    final city = firstPart([
      raw['city'],
      raw['locality'],
      raw['town'],
      raw['postTown'],
      _cityFromManualParts(locationParts, addressLine1),
    ]);
    final county = firstPart([
      raw['county'],
      raw['countyState'],
      raw['county'],
      raw['state'],
      raw['region'],
    ]);
    final postcode = firstPart([
      raw['postcode'],
      raw['postalCode'],
      raw['zip'],
      extractUkPostcode(manualAddress ?? suggestion?.description),
    ]);
    final country = firstPart([
      raw['country'],
      _countryFromManualParts(locationParts),
    ]);
    final formattedAddress = joinDistinctParts([
      addressLine1,
      addressLine2,
      city,
      county,
      postcode,
      country,
    ]);
    final lat = toDouble(
      latitude ?? raw['latitude'] ?? raw['lat'] ?? suggestion?.lat,
    );
    final lng = toDouble(
      longitude ?? raw['longitude'] ?? raw['lng'] ?? suggestion?.lng,
    );

    return {
      'addressId': firstPart([addressId, raw['addressId'], raw['id']]),
      'formattedAddress': formattedAddress,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'buildingName': buildingName,
      'apartment': apartment,
      'floor': floor,
      'entranceInstructions': entranceInstructions,
      'city': city,
      'county': county,
      'postcode': postcode,
      'country': country,
      'placeId': firstPart([placeId, raw['placeId'], suggestion?.placeId]),
      'latitude': lat,
      'longitude': lng,
      'verified': toBool(verified ?? raw['verified']),
      'source': firstPart([
        source,
        raw['source'],
        suggestion != null ? 'autocomplete' : null,
        manualAddress != null ? 'manual' : null,
      ]),
      'createdAt': firstPart([createdAt, raw['createdAt']]),
      'updatedAt': firstPart([updatedAt, raw['updatedAt']]),
      // Compatibility aliases for older readers while products migrate to the
      // canonical Address object above.
      'countyState': county,
      'lat': lat,
      'lng': lng,
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
      normalized['county'],
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
      components: {...suggestion.components, ...normalized},
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
        address['county'],
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

  static bool? toBool(Object? value) {
    if (value is bool) return value;
    final cleaned = clean(value).toLowerCase();
    if (cleaned == 'true' || cleaned == 'yes' || cleaned == '1') return true;
    if (cleaned == 'false' || cleaned == 'no' || cleaned == '0') return false;
    return null;
  }
}
