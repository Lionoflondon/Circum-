import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image_codec;

const int irisInferenceLongestEdge = 1280;
const int irisInferenceJpegQuality = 82;

Map<String, Object> prepareIrisInferenceImage(Map<String, Object> input) {
  final original = input['bytes']! as Uint8List;
  final originalType = input['contentType']! as String;
  try {
    final decoded = image_codec.decodeImage(original);
    if (decoded == null) return _unchanged(original, originalType);

    final longest = math.max(decoded.width, decoded.height);
    final inferenceImage = longest > irisInferenceLongestEdge
        ? image_codec.copyResize(
            decoded,
            width: decoded.width >= decoded.height
                ? irisInferenceLongestEdge
                : null,
            height: decoded.height > decoded.width
                ? irisInferenceLongestEdge
                : null,
            interpolation: image_codec.Interpolation.linear,
          )
        : decoded;
    final jpeg = Uint8List.fromList(
      image_codec.encodeJpg(
        inferenceImage,
        quality: irisInferenceJpegQuality,
      ),
    );
    final png = Uint8List.fromList(image_codec.encodePng(inferenceImage));
    final encoded = jpeg.length <= png.length ? jpeg : png;
    final encodedType = identical(encoded, jpeg) ? 'image/jpeg' : 'image/png';
    if (longest <= irisInferenceLongestEdge &&
        encoded.length >= original.length) {
      return _unchanged(original, originalType);
    }
    return {
      'bytes': encoded,
      'contentType': encodedType,
      'optimized': true,
    };
  } catch (_) {
    return _unchanged(original, originalType);
  }
}

Map<String, Object> _unchanged(Uint8List bytes, String contentType) => {
      'bytes': bytes,
      'contentType': contentType,
      'optimized': false,
    };
