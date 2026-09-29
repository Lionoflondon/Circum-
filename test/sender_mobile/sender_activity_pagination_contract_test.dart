import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Activity keeps an unselected source cursor for the next merged page', () {
    final source = File('lib/app/sender_mobile/sender_activity.dart').readAsStringSync();
    expect(source, contains('const _senderActivityPageSize = 20;'));
    expect(source, contains(".orderBy(FieldPath.documentId, descending: true)"));
    expect(source, contains('startAfter(['));
    expect(source, contains('senderActivityTimestamp'));
    expect(source, isNot(contains('_setActivityCursorFromDocument')));
  });

  test('Activity load-more has a bounded retry state', () {
    final source = File('lib/app/sender_mobile/sender_activity.dart').readAsStringSync();
    expect(source, contains('_loadMoreError'));
    expect(source, contains("'More activity is unavailable right now. Please retry.'"));
    expect(source, contains("'Load more activity'"));
    expect(source, contains("'Retry'"));
  });
}
