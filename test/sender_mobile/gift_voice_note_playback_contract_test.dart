import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gift Story renders sender voice notes with playback controls', () {
    final storySource =
        File('lib/app/sender_mobile/gift_story_view.dart').readAsStringSync();
    final policySource =
        File('lib/app/gifts/gift_story_studio_policy.dart').readAsStringSync();

    expect(policySource, contains('GiftStorySlideType.voiceNote'));
    expect(policySource, contains('mediaUrl: senderVoiceNoteUrl'));
    expect(storySource, contains('class _VoiceNoteSlide'));
    expect(storySource, contains('SenderGiftVoicePlayback'));
    expect(storySource, contains('Play voice note'));
    expect(storySource, contains('Pause voice note'));
    expect(
      storySource,
      isNot(contains(
        'GiftStorySlideType.note || GiftStorySlideType.voiceNote => _NoteSlide',
      )),
    );
  });
}
