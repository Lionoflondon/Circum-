import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Send flow never falls back to bright blank loading surfaces', () {
    final legacySendHome =
        File('lib/app/send_package/view/home.dart').readAsStringSync();
    final sendChat =
        File('lib/app/send_package/view/ride_chats.dart').readAsStringSync();

    expect(legacySendHome, contains('Color(0xFF07090F)'));
    expect(legacySendHome, contains('_SendDarkBackdrop'));
    expect(legacySendHome, isNot(contains('color: Colors.red')));

    expect(sendChat, contains('AppTokens.background'));
    expect(sendChat, contains('_ChatLoadingState'));
    expect(sendChat, contains('Messages are unavailable'));
    expect(sendChat,
        isNot(contains('Center(child: CircularProgressIndicator())')));
    expect(sendChat, isNot(contains('backgroundColor: Colors.white')));
  });
}
