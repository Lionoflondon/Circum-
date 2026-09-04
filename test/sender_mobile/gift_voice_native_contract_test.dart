import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native Gift voice remains honestly disabled for this release', () {
    final selector = File('lib/app/sender_mobile/gift_voice_recorder.dart')
        .readAsStringSync();
    final stub = File(
      'lib/app/sender_mobile/gift_voice_recorder_stub.dart',
    ).readAsStringSync();

    expect(selector, isNot(contains('dart.library.io')));
    expect(selector,
        contains("dart.library.html) 'gift_voice_recorder_web.dart'"));
    expect(stub, contains('bool get isSupported => false'));
  });

  test('native platform permission declarations are present', () {
    final android = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final ios = File('ios/Runner/Info.plist').readAsStringSync();

    expect(android, contains('android.permission.RECORD_AUDIO'));
    expect(ios, contains('NSMicrophoneUsageDescription'));
    expect(ios, contains('voice note for your Gift delivery'));
  });

  test('storage accepts canonical mobile MIME without weakening ownership', () {
    final rules = File('storage.rules').readAsStringSync();

    expect(rules, contains('isGiftVoiceNoteOwner(requestId)'));
    expect(rules, contains('audio/mp4'));
    expect(
      rules,
      contains('allow read: if isAdmin() || isGiftVoiceNoteOwner(requestId);'),
    );
  });
}
