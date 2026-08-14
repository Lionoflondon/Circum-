import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;

class BitmapDescriptorHelper {
  static final Map<String, Future<BitmapDescriptor>> _cache = {};

  static Future<BitmapDescriptor> getBitmapDescriptorFromSvgAsset(
    String assetName, [
    Size size = const Size(42, 42),
  ]) async {
    final cacheKey = '$assetName:${size.width}x${size.height}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    final descriptor = _buildBitmapDescriptorFromSvgAsset(assetName, size);
    _cache[cacheKey] = descriptor;
    return descriptor;
  }

  static Future<BitmapDescriptor> _buildBitmapDescriptorFromSvgAsset(
    String assetName,
    Size size,
  ) async {
    final pictureInfo = await vg.loadPicture(SvgAssetLoader(assetName), null);

    final devicePixelRatio = ui.PlatformDispatcher.instance.views.isEmpty
        ? 1.0
        : ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    int width = (size.width * devicePixelRatio).toInt();
    int height = (size.height * devicePixelRatio).toInt();

    final scaleFactor = math.min(
      width / pictureInfo.size.width,
      height / pictureInfo.size.height,
    );

    final recorder = ui.PictureRecorder();

    ui.Canvas(recorder)
      ..scale(scaleFactor)
      ..drawPicture(pictureInfo.picture);

    final rasterPicture = recorder.endRecording();

    final image = rasterPicture.toImageSync(width, height);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;

    return BitmapDescriptor.bytes(
      bytes.buffer.asUint8List(),
      width: size.width,
      height: size.height,
      imagePixelRatio: devicePixelRatio,
    );
  }
}
