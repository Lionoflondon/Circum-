import 'package:flutter_test/flutter_test.dart';
import 'package:circum/website/shared/sender_checkout_return.dart';

void main() {
  test('return stays on each approved session origin and the Sender route', () {
    for (final origin in [
      'https://circumuk.com',
      'https://www.circumuk.com',
      'https://circum-2797c.web.app',
      'https://circum-2797c.firebaseapp.com',
    ]) {
      final result = senderWebsiteCheckoutReturn(
          Uri.parse('$origin/send/profile?untrusted=value#fragment'));
      expect(result.origin, origin);
      expect(result.path, '/send');
      expect(result.hasQuery, isFalse);
      expect(result.hasFragment, isFalse);
    }
  });

  test('lookalike, insecure and non-default-port origins cannot receive returns',
      () {
    for (final page in [
      'https://circumuk.com.example.invalid/send',
      'http://circumuk.com/send',
      'https://circumuk.com:444/send',
      'https://example.invalid/send',
      '/send',
    ]) {
      expect(senderWebsiteCheckoutReturn(Uri.parse(page)).toString(),
          'https://circumuk.com/send');
    }
  });
}
