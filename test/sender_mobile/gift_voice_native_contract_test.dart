import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:circum/app/sender_mobile/gift_voice_recorder_native.dart';

void main() {
  test('native Gift voice is selected and uses bounded AAC recording', () {
    final selector = File('lib/app/sender_mobile/gift_voice_recorder.dart')
        .readAsStringSync();
    final native = File(
      'lib/app/sender_mobile/gift_voice_recorder_native.dart',
    ).readAsStringSync();

    expect(selector,
        contains("dart.library.io) 'gift_voice_recorder_native.dart'"));
    expect(native, contains('hasPermission()'));
    expect(native, contains('AudioEncoder.aacLc'));
    expect(native, contains("mimeType: 'audio/mp4'"));
    expect(native, contains('.timeout(_operationTimeout)'));
    expect(native, contains('_recorder.cancel()'));
    expect(native, contains('setFilePath(localUrl)'));
    expect(native, isNot(contains('print(')));
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

  test('stale native Gift voice temp files are removed safely', () async {
    final directory =
        await Directory.systemTemp.createTemp('circum_voice_test_');
    addTearDown(() => directory.delete(recursive: true));
    final stale = File('${directory.path}/stale.m4a');
    final fresh = File('${directory.path}/fresh.m4a');
    final unrelated = File('${directory.path}/keep.txt');
    await stale.writeAsBytes([1]);
    await fresh.writeAsBytes([2]);
    await unrelated.writeAsBytes([3]);
    await stale
        .setLastModified(DateTime.now().subtract(const Duration(days: 2)));

    await SenderGiftVoiceRecorder.cleanupStaleFiles(directory: directory);

    expect(await stale.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
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
