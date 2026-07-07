import '../send_package/models/suggestions.m.dart';

class GiftAddressNormalizer {
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
    final parts = values
        .map(clean)
        .where((value) => value.isNotEmpty)
        .where((value) => value != ',')
        .toList();
    return parts.join(separator);
  }

  static Map<String, dynamic> normalizedComponents(
    Suggestion? suggestion, {
    String? manualAddress,
  }) {
    final raw = suggestion?.components ?? const <String, dynamic>{};
    final streetNumber = clean(raw['streetNumber'] ??
        raw['buildingNumber'] ??
        raw['premise'] ??
        raw['subBuildingName']);
    final route = clean(raw['route'] ?? raw['street'] ?? raw['thoroughfare']);
    final line1FromParts = joinParts(
      [streetNumber, route],
      separator: ' ',
    );
    final manualParts = (manualAddress ?? '')
        .split(',')
        .map(clean)
        .where((value) => value.isNotEmpty)
        .toList();
    final addressLine1 =
        clean(raw['addressLine1'] ?? raw['line1'] ?? raw['displayAddressLine1'])
                .isNotEmpty
            ? clean(raw['addressLine1'] ??
                raw['line1'] ??
                raw['displayAddressLine1'])
            : line1FromParts.isNotEmpty
                ? line1FromParts
                : manualParts.isNotEmpty
                    ? manualParts.first
                    : clean(suggestion?.mainText);
    final addressLine2 = clean(raw['addressLine2'] ?? raw['line2']);
    final city = clean(raw['city'] ??
        raw['locality'] ??
        raw['town'] ??
        raw['postTown'] ??
        (manualParts.length >= 3
            ? manualParts[manualParts.length - 3]
            : manualParts.length >= 2
                ? manualParts[manualParts.length - 2]
                : ''));
    final postcode = clean(raw['postcode'] ??
        raw['postalCode'] ??
        (manualParts.length >= 2 ? manualParts[manualParts.length - 2] : ''));
    final country = clean(
        raw['country'] ?? (manualParts.isNotEmpty ? manualParts.last : ''));
    final formattedAddress = joinParts([
      addressLine1,
      addressLine2,
      city,
      postcode,
      country,
    ]);

    return {
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'postcode': postcode,
      'country': country,
      'formattedAddress': formattedAddress,
      'placeId': clean(suggestion?.placeId),
      'lat': suggestion?.lat,
      'lng': suggestion?.lng,
    }..removeWhere((key, value) => value == null || clean(value).isEmpty);
  }

  static bool hasRequiredFields(
    Suggestion? suggestion, {
    String? manualAddress,
  }) {
    final fields = normalizedComponents(
      suggestion,
      manualAddress: manualAddress,
    );
    return clean(fields['addressLine1']).isNotEmpty &&
        clean(fields['city']).isNotEmpty &&
        clean(fields['postcode']).isNotEmpty &&
        clean(fields['country']).isNotEmpty;
  }

  static Suggestion cleanSuggestion(Suggestion suggestion) {
    final normalized = normalizedComponents(
      suggestion,
      manualAddress: suggestion.description,
    );
    final description = clean(normalized['formattedAddress']).isNotEmpty
        ? clean(normalized['formattedAddress'])
        : clean(suggestion.description);
    final mainText = clean(normalized['addressLine1']).isNotEmpty
        ? clean(normalized['addressLine1'])
        : clean(suggestion.mainText);
    final subText = joinParts([
      normalized['city'],
      normalized['postcode'],
      normalized['country'],
    ]);
    return Suggestion(
      placeId: clean(suggestion.placeId).isEmpty
          ? description
          : clean(suggestion.placeId),
      description: description,
      subText: subText.isEmpty ? description : subText,
      mainText: mainText,
      lat: suggestion.lat,
      lng: suggestion.lng,
      components: normalized,
    );
  }
}
