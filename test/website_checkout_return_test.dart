import 'package:flutter_test/flutter_test.dart';
import 'package:circum/website/shared/website_checkout_return.dart';

void main() {
  final expectedRoutes = {
    WebsiteCheckoutReturn.sender: '/send',
    WebsiteCheckoutReturn.business: '/?app=business',
    WebsiteCheckoutReturn.healthSuccess: '/send/health?health=success',
    WebsiteCheckoutReturn.healthCancelled: '/send/health?health=cancelled',
  };
  test('all payment returns preserve each approved session origin and route',
      () {
    for (final origin in [
      'https://circumuk.com',
      'https://www.circumuk.com',
      'https://circum-2797c.web.app',
      'https://circum-2797c.firebaseapp.com',
    ]) {
      for (final entry in expectedRoutes.entries) {
        final result = websiteCheckoutReturn(
            Uri.parse('$origin/send/profile?untrusted=value#fragment'),
            entry.key);
        expect(result.toString(), '$origin${entry.value}');
        expect(result.origin, origin);
        expect(result.hasFragment, isFalse);
      }
    }
  });
  test('lookalike, insecure and non-default-port origins never receive returns',
      () {
    for (final page in [
      'https://circumuk.com.example.invalid/send',
      'http://circumuk.com/send',
      'https://circumuk.com:444/send',
      'https://example.invalid/send',
      '/send',
    ]) {
      for (final entry in expectedRoutes.entries) {
        expect(websiteCheckoutReturn(Uri.parse(page), entry.key).toString(),
            'https://circumuk.com${entry.value}');
      }
    }
  });
}
