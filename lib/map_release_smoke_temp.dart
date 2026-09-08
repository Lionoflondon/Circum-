import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() => runApp(const _MapSmokeApp());

class _MapSmokeApp extends StatelessWidget {
  const _MapSmokeApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(51.5074, -0.1278),
                zoom: 13,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xE6101724)),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'CIRCUM SENDER · PRODUCTION MAP CHECK',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
