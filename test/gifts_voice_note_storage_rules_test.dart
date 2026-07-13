import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sender gift voice notes have a dedicated storage rule', () {
    final rules = File('storage.rules').readAsStringSync();

    expect(
      rules,
      contains('match /gift_requests/{requestId}/voice/{fileName}'),
    );
    expect(
      rules,
      contains(
        "requestId.matches('^' + request.auth.uid + '_[0-9]+\$')",
      ),
    );
    expect(rules, contains('request.resource.size <= 60 * 1024 * 1024'));
    for (final mime in const [
      'audio/webm',
      'audio/mpeg',
      'audio/mp4',
      'audio/aac',
      'audio/ogg',
    ]) {
      expect(rules, contains(mime));
    }
    expect(
      rules,
      contains(
        'allow create, update: if isGiftVoiceNoteOwner(requestId) && isSafeGiftVoiceNoteUpload();',
      ),
    );
    expect(rules, contains('allow delete: if isSuperAdmin();'));
    expect(rules, isNot(contains('allow read, write: if signedIn();')));
  });
}
