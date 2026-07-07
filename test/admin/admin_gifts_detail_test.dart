import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Admin Gifts detail surfaces brief voice interests and payment first',
      () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    final briefIndex = source.indexOf('IRIS Gift Brief');
    final voiceIndex = source.indexOf('Voice Note');
    final interestsIndex = source.indexOf('Custom Interests Review');
    final paymentIndex = source.indexOf('Payment Breakdown');
    final workspaceIndex = source.indexOf('Gifts Team Workspace');
    final rawIndex = source.indexOf('Raw Request Data');

    expect(briefIndex, greaterThan(-1));
    expect(voiceIndex, greaterThan(briefIndex));
    expect(interestsIndex, greaterThan(voiceIndex));
    expect(paymentIndex, greaterThan(interestsIndex));
    expect(workspaceIndex, greaterThan(paymentIndex));
    expect(rawIndex, greaterThan(workspaceIndex));
    expect(source, contains('Recipient summary'));
    expect(source, contains('Voice summary'));
    expect(source, contains('Play voice note'));
    expect(source, contains('Approve, reject, or merge these'));
    expect(source, contains('Roth applied'));
    expect(source, contains('Stripe session'));
    expect(source, contains('Assigned Curator'));
    expect(source, contains('Rich internal notes'));
    expect(source, contains('Selected experience'));
    expect(source, contains('Ready for Procurement'));
    expect(source, contains("'giftsTeamWorkspace'"));
    expect(source, contains("'giftIrisLearning'"));
    expect(source, contains('Gift workspace updated'));
  });
}
