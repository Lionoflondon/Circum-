// For storing our result
class Suggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String subText;
  final double? lat;
  final double? lng;
  final Map<String, dynamic> components;

  Suggestion({
    required this.placeId,
    required this.description,
    required this.subText,
    required this.mainText,
    this.lat,
    this.lng,
    this.components = const {},
  });

  @override
  String toString() {
    return 'Suggestion(description: $description, placeId: $placeId, subText: $subText, mainText: $mainText, lat: $lat, lng: $lng, components: $components)';
  }
}
