import 'package:circum/app/admin/newsletter_audience.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audience CSV escapes quotes and prevents spreadsheet formulas', () {
    expect(newsletterCsvCell('a"b@example.com'), '"a""b@example.com"');
    expect(newsletterCsvCell('=HYPERLINK("url")'), '"\'=HYPERLINK(""url"")"');
    expect(newsletterCsvCell('+test@example.com'), '"\'+test@example.com"');
    expect(newsletterCsvCell('normal@example.com'), '"normal@example.com"');
  });
}
