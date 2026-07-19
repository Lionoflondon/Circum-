import 'package:circum/app/sender_mobile/sender_mobile_home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender dashboard service copy is production ready', () {
    expect(
      senderMobileDashboardServiceSubtitles['Gifts'],
      'Thoughtful gifts, delivered.',
    );
  });
}
