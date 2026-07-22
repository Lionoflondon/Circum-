import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Gifts voice recording uses the canonical Circum media layer', () {
    final view = File('lib/app/sender_mobile/gift_voice_note_view.dart')
        .readAsStringSync();
    final story =
        File('lib/app/sender_mobile/gift_story_view.dart').readAsStringSync();
    final media = File('lib/app/media/circum_media.dart').readAsStringSync();

    expect(view, contains('CircumVoiceRecorder'));
    expect(view, contains('CircumVoicePlayback'));
    expect(view, contains('CircumMediaStorage'));
    expect(view, isNot(contains('FirebaseStorage.instance.ref')));
    expect(story, contains('CircumVoicePlayback'));
    expect(media, contains('SenderGiftVoiceRecorder'));
    expect(media, contains('SenderGiftVoicePlayback'));
  });

  test('Gifts voice metadata includes lifecycle and ownership fields', () {
    final draft = File('lib/app/sender_mobile/gift_journey_draft.dart')
        .readAsStringSync();
    final media = File('lib/app/media/circum_media.dart').readAsStringSync();

    expect(draft, contains("'uploadStatus': uploadStatus"));
    expect(draft, contains("'retryState': retryState"));
    expect(draft, contains("'version': version"));
    expect(draft, contains("'ownerId': ownerId"));
    expect(media, contains("'uploadStatus': 'uploaded'"));
    expect(media, contains("'retryState': 'none'"));
    expect(media, contains("'ownerId': user.uid"));
  });

  test('Gifts voice storage lifecycle supports owner cleanup', () {
    final view = File('lib/app/sender_mobile/gift_voice_note_view.dart')
        .readAsStringSync();
    final media = File('lib/app/media/circum_media.dart').readAsStringSync();
    final rules = File('storage.rules').readAsStringSync();

    expect(view, contains('_mediaStorage.deleteMedia'));
    expect(media, contains('Future<void> deleteMedia'));
    expect(
      rules,
      contains(
          'allow delete: if isSuperAdmin() || isGiftVoiceNoteOwner(requestId);'),
    );
  });

  test('Gift Story app access is backend-led and token deep-linkable', () {
    final story =
        File('lib/app/sender_mobile/gift_story_view.dart').readAsStringSync();
    final home = File('lib/app/sender_mobile/sender_mobile_home.dart')
        .readAsStringSync();
    final preview = File('lib/app/sender_mobile/sender_mobile_preview.dart')
        .readAsStringSync();

    expect(preview, contains('GiftStoryView.routeName'));
    expect(home, contains('case GiftStoryView.routeName'));
    expect(story, contains("'resolveGiftStoryAccess'"));
    expect(story, contains("'getGiftStoryActionState'"));
    expect(story, contains("data['authenticated'] == true"));
    expect(story, contains('recordGiftStoryGuestEvent'));
    expect(story, contains('Your Gift Story is ready.'));
    expect(story, contains('Maybe later'));
    expect(story, contains('_ensureAccountForOwnership'));
  });
}
