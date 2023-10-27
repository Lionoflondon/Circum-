import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapControllerSingleton {
  static final MapControllerSingleton _singleton =
      MapControllerSingleton._internal();
  GoogleMapController? _controller;

  factory MapControllerSingleton() {
    return _singleton;
  }

  MapControllerSingleton._internal();

  void setController(GoogleMapController controller) {
    _controller = controller;
  }

  GoogleMapController? getController() {
    return _controller;
  }
}
