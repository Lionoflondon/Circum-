// For storing our result
class Suggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String subText;

  Suggestion(
      {required this.placeId,
      required this.description,
      required this.subText,
      required this.mainText});

  @override
  String toString() {
    return 'Suggestion(description: $description, placeId: $placeId, subText: $subText, mainText: $mainText, )';
  }
}
