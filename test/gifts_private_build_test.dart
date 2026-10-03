import 'package:circum/gifts_test_main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private entry point refuses missing authorization flag and LIVE mode',
      () {
    expect(() => validateGiftsTestBuild(enabled: false, mode: 'test'),
        throwsStateError);
    expect(() => validateGiftsTestBuild(enabled: true, mode: 'live'),
        throwsStateError);
    expect(() => validateGiftsTestBuild(enabled: true, mode: ''),
        throwsStateError);
    expect(() => validateGiftsTestBuild(enabled: true, mode: 'test'),
        returnsNormally);
  });
}
