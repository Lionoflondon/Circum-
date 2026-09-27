import 'package:flutter_test/flutter_test.dart';
import 'package:circum/app/send_package/models/canonical_iris_result.dart';

void main() {
  test('canonical IRIS preserves safe prohibited guidance', () {
    final result = CanonicalIrisResult.fromCallable({
      'itemName': 'weed',
      'recommendation': {
        'estimatedWeightKg': 2,
        'recommendedVehicle': 'Motorbike',
      },
      'compliance': {
        'status': 'prohibited',
        'customerMessage': 'This item cannot be carried by Circum.',
      },
    });
    expect(result.complianceStatus, 'prohibited');
    expect(result.complianceMessage, 'This item cannot be carried by Circum.');
  });

  test('legacy IRIS response remains compatible', () {
    final result = CanonicalIrisResult.fromCallable({
      'itemName': 'book',
      'recommendation': {'estimatedWeightKg': 1},
    });
    expect(result.complianceStatus, 'allowed');
    expect(result.complianceMessage, isNull);
  });
}
