import 'dart:async';
import 'dart:io';
import 'package:circum/app/sender_mobile/gift_voice_completion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing browser stop event times out and releases recording resources',
      () async {
    var cleaned = 0;
    final result = GiftVoiceCompletion<String>(
        timeout: const Duration(milliseconds: 5), onSettled: () => cleaned++);
    await expectLater(result.future, throwsA(isA<TimeoutException>()));
    expect(result.isCompleted, isTrue);
    expect(cleaned, 1);
    result.complete('late browser event');
    result.fail(StateError('late error'));
    expect(cleaned, 1);
  });
  test('blob read failure is terminal and cannot be replaced by a late success',
      () async {
    var cleaned = 0;
    final result = GiftVoiceCompletion<String>(
        timeout: const Duration(seconds: 1), onSettled: () => cleaned++);
    final assertion = expectLater(result.future, throwsStateError);
    result.fail(StateError('blob read failed'));
    result.complete('late data');
    await assertion;
    expect(cleaned, 1);
  });
  test('successful stop produces one result and cancels the deadline',
      () async {
    var cleaned = 0;
    final result = GiftVoiceCompletion<String>(
        timeout: const Duration(milliseconds: 5), onSettled: () => cleaned++);
    result.complete('audio');
    expect(await result.future, 'audio');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(cleaned, 1);
  });
  test('cancellation settles a pending stop request', () async {
    final result = GiftVoiceCompletion<String>(
        timeout: const Duration(seconds: 1), onSettled: () {});
    final assertion = expectLater(result.future, throwsStateError);
    result.fail(StateError('cancelled'));
    await assertion;
    expect(result.isCompleted, isTrue);
  });
  test(
      'browser wiring bounds permissions and blob reads and rejects late streams',
      () {
    final source = File('lib/app/sender_mobile/gift_voice_recorder_web.dart')
        .readAsStringSync();
    expect(source, contains('generation != _generation'));
    expect(source, contains('track.stop()'));
    expect(source, contains('.timeout(_operationTimeout)'));
    expect(source, contains('GiftVoiceCompletion<SenderGiftRecordedAudio>'));
    expect(source, contains('reader.abort()'));
    expect(source, contains('completer.isCompleted'));
  });
  test('cancelled or disposed recording does not start a new upload', () {
    final source = File('lib/app/sender_mobile/gift_voice_note_view.dart')
        .readAsStringSync();
    final start = source.indexOf('final audio = await _recorder.stop();');
    final end =
        source.indexOf('_mediaStorage.uploadGiftVoiceNote(audio)', start);
    expect(source.substring(start, end),
        contains('!mounted || generation != _recordingGeneration'));
    expect(source, contains('if (_recordingOperationPending) return;'));
    expect(source, contains('_recordingOperationPending = false;'));
  });
}
