import 'package:dio/dio.dart';
// import 'package:http/http.dart';

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

class PlaceCoordinate {
  final double lat;
  final double lng;

  PlaceCoordinate({required this.lat, required this.lng});
}

class PlaceApiProvider {
  // final client = Client();
  Dio dio = Dio();
  PlaceApiProvider(this.sessionToken);

  final sessionToken;

  static String mapKey = 'AIzaSyDWH0L6pjdf2W_ZZrjfv6z5OvMZQ2TVNMI';
  // static final String iosKey = 'YOUR_API_KEY_HERE';
  final apiKey = mapKey;

  Future<List<Suggestion>> fetchSuggestions(String input, String lang) async {
    final response = await dio.get(
        'https://maps.googleapis.com/maps/api/place/queryautocomplete/json?input=$input&types=address&language=$lang&components=country:ng&key=$apiKey&sessiontoken=$sessionToken');

    // print("Recieving Data");

    if (response.statusCode == 200) {
      final result = response.data;
      // print(response.data);
      if (result['status'] == 'OK') {
        // compose suggestions in a list
        return result['predictions']
            .where((p) =>
                p['place_id'] != null &&
                p['description'] != null &&
                p['structured_formatting'] != null &&
                p['structured_formatting']['secondary_text'] != null &&
                p['structured_formatting']['main_text'] != null)
            .map<Suggestion>((p) {
          // print(p);
          // if (p['place_id'] != null &&
          //     p['description'] != null &&
          //     p['structured_formatting'] != null &&
          //     p['structured_formatting']['secondary_text'] != null &&
          //     p['structured_formatting']['main_text'] != null) {
          return Suggestion(
              placeId: p['place_id'],
              description: p['description'],
              subText: p['structured_formatting']['secondary_text'],
              mainText: p['structured_formatting']['main_text']);
        }).toList();
      }
      if (result['status'] == 'ZERO_RESULTS') {
        return [];
      }
      throw Exception(result['error_message']);
    } else {
      throw Exception('Failed to fetch suggestion');
    }
  }

  Future<PlaceCoordinate> fetchPlaceDetails(String placeId, String lang) async {
    final response = await dio.get(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$apiKey&language=$lang&sessiontoken=$sessionToken');

    print(response.statusCode);

    if (response.statusCode == 200) {
      final result = response.data;
      if (result['status'] == 'OK') {
        print(result['result']['geometry']['location']);

        return PlaceCoordinate(
            lat: result['result']['geometry']['location']['lat'],
            lng: result['result']['geometry']['location']['lng']);
      }
      print(result['status']);
      throw Exception(result['error_message']);
    } else {
      throw Exception("Couldn't fetch location details");
    }
  }
}
