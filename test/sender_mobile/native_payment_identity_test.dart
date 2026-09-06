import 'package:circum/app/sender_mobile/native_payment_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('retry and concurrent entry retain one Gift identity', () async {
    final ids = await Future.wait(List.generate(
        10,
        (i) => NativePaymentIdentity.reserve(
            uid: 'sender', flow: 'gift', candidate: 'gift-$i')));
    expect(ids.toSet(), {'gift-0'});
  });

  test('cold restart restores durable identity without inferring payment',
      () async {
    SharedPreferences.setMockInitialValues({
      'circum.pending-payment.v1.sender.gift': 'original',
    });
    expect(
        await NativePaymentIdentity.reserve(
            uid: 'sender', flow: 'gift', candidate: 'new'),
        'original');
  });

  test('accounts and Gift versus delivery identities cannot cross', () async {
    expect(
        await NativePaymentIdentity.reserve(
            uid: 'a', flow: 'gift', candidate: 'gift'),
        'gift');
    expect(
        await NativePaymentIdentity.reserve(
            uid: 'b', flow: 'gift', candidate: 'other'),
        'other');
    expect(
        await NativePaymentIdentity.reserve(
            uid: 'a', flow: 'delivery', candidate: 'delivery'),
        'delivery');
  });

  test('stale return cannot clear newer payment; confirmed identity can clear',
      () async {
    await NativePaymentIdentity.reserve(
        uid: 'a', flow: 'gift', candidate: 'current');
    await NativePaymentIdentity.resolve(
        uid: 'a', flow: 'gift', expected: 'stale');
    expect(
        await NativePaymentIdentity.reserve(
            uid: 'a', flow: 'gift', candidate: 'new'),
        'current');
    await NativePaymentIdentity.resolve(
        uid: 'a', flow: 'gift', expected: 'current');
    expect(
        await NativePaymentIdentity.reserve(
            uid: 'a', flow: 'gift', candidate: 'new'),
        'new');
  });
}
