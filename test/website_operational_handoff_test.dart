import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public Website hands operational Sender and Rider routes off before Flutter starts', () {
    final index = File('web/index.html').readAsStringSync();
    expect(index, contains("path === '/send'"));
    expect(index, contains("path === '/rider'"));
    expect(index, contains("window.location.replace"));
    expect(index, contains('https://circum-app-2797c.web.app/'));
    expect(index, contains('https://circum-rider-2797c.web.app/'));
    expect(index.indexOf('handOffOperationalProducts'), lessThan(index.indexOf('flutter_bootstrap.js')));
  });

  test('public Website blocks protected interaction when App Check startup fails', () {
    final main = File('lib/main_public_web.dart').readAsStringSync();
    expect(main, contains('await initializeCircumAppCheck()'));
    expect(main, contains('_WebsiteSecurityRecovery'));
    expect(main, isNot(contains('_activateAppCheckAfterStartup')));
  });
}
