import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Admin Gifts detail surfaces brief voice interests and payment first',
      () {
    final source = File('lib/web_sender_app.dart').readAsStringSync();
    final briefIndex = source.indexOf('IRIS Gift Brief');
    final voiceIndex = source.indexOf('_adminGiftVoiceNotePanel(item: item');
    final interestsIndex =
        source.indexOf('_adminGiftCustomInterestPanel(customInterests)');
    final paymentIndex = source.indexOf('Payment Breakdown');
    final workspaceIndex = source.indexOf('Gifts Team Workspace');
    final rawIndex = source.indexOf('Raw Request Data');

    expect(briefIndex, greaterThan(-1));
    expect(voiceIndex, greaterThan(-1));
    expect(interestsIndex, greaterThan(voiceIndex));
    expect(paymentIndex, greaterThan(interestsIndex));
    expect(workspaceIndex, greaterThan(paymentIndex));
    expect(rawIndex, greaterThan(workspaceIndex));
    expect(source, contains('Recipient summary'));
    expect(source, contains('Voice summary'));
    expect(source, contains('No voice note was provided.'));
    expect(source, contains('Transcript'));
    expect(source, contains('AI summary'));
    expect(source, contains('Uploaded at'));
    expect(source, contains('Format'));
    expect(source, contains('class _CircumVoiceAudioPlayer'));
    expect(source, contains('html.AudioElement(widget.url)'));
    expect(source, contains('onTimeUpdate'));
    expect(source, contains('currentTime = value'));
    expect(source, contains('Bulk accept'));
    expect(source, contains('Bulk reject'));
    expect(source, contains('Add New Interest'));
    expect(source, contains('Roth applied'));
    expect(source, contains('Stripe session'));
    expect(source, contains('Assigned Curator'));
    expect(source, contains('Rich internal notes'));
    expect(source, contains('Selected experience'));
    expect(source, contains('Ready for Procurement'));
    expect(source, contains('IRIS Review'));
    expect(source, contains('Approved gift ideas'));
    expect(source, contains('Rejected suggestions'));
    expect(source, contains('Manual changes'));
    expect(source, contains('Gift specialist notes'));
    expect(source, contains('IRIS Gift Review'));
    expect(source, contains('Supplier link'));
    expect(source, contains('Order reference'));
    expect(source, contains('Receipt upload / URL'));
    expect(source, contains('Invoice upload / URL'));
    expect(source, contains('Include sender voice note'));
    expect(source, contains('Music ducking level'));
    expect(source, contains('Playback timeline'));
    expect(source, contains('giftStoryAudioMix'));
    expect(source, contains('nonDestructive'));
    expect(source, contains("'giftsTeamWorkspace'"));
    expect(source, contains("'giftIrisLearning'"));
    expect(source, contains('Gift workspace updated'));
    expect(source, contains('Gift request approved and saved.'));
  });
}
