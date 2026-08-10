import 'dart:typed_data';

import 'package:circum/app/sender_mobile/iris_inference_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;

void main() {
  test('large inference images are bounded without mutating original evidence',
      () {
    final source = image_codec.Image(width: 2400, height: 1600);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgba(x, y, x % 256, y % 256, (x + y) % 256, 255);
      }
    }
    final original = Uint8List.fromList(image_codec.encodePng(source));
    final originalCopy = Uint8List.fromList(original);

    final result = prepareIrisInferenceImage({
      'bytes': original,
      'contentType': 'image/png',
    });
    final payload = result['bytes']! as Uint8List;
    final decoded = image_codec.decodeImage(payload)!;

    expect(result['optimized'], isTrue);
    expect(result['contentType'], anyOf('image/jpeg', 'image/png'));
    expect(decoded.width, irisInferenceLongestEdge);
    expect(decoded.height, lessThan(irisInferenceLongestEdge));
    expect(payload, isNotEmpty);
    expect(original, orderedEquals(originalCopy));
  });

  test('already efficient image is never replaced by a larger payload', () {
    final source = image_codec.Image(width: 32, height: 32);
    final original = Uint8List.fromList(
      image_codec.encodeJpg(source, quality: 40),
    );

    final result = prepareIrisInferenceImage({
      'bytes': original,
      'contentType': 'image/jpeg',
    });

    expect(
      (result['bytes']! as Uint8List).length,
      lessThanOrEqualTo(original.length),
    );
    expect(result['contentType'], anyOf('image/jpeg', 'image/png'));
  });

  test('invalid input fails open to the original evidence bytes', () {
    final original = Uint8List.fromList([1, 2, 3, 4]);
    final result = prepareIrisInferenceImage({
      'bytes': original,
      'contentType': 'image/png',
    });

    expect(result['optimized'], isFalse);
    expect(result['bytes'], same(original));
  });
}
