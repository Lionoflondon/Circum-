import 'package:circum/website/shared/privacy/cookie_consent_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1440, 900),
    const Size(844, 390)
  ]) {
    testWidgets('consent remains usable at $size with safe areas and zoom',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var rejected = 0;
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
        data: MediaQueryData(
            size: size,
            padding: const EdgeInsets.only(bottom: 34),
            textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
            body: Column(children: [
          Expanded(
              child: Center(
                  child: TextButton(
                      onPressed: () {}, child: const Text('Navigation')))),
          CookieConsentPanel(
              onReject: () => rejected++, onCustomise: () {}, onAccept: () {}),
        ])),
      )));
      expect(tester.takeException(), isNull);
      final navigation = tester.getRect(find.text('Navigation'));
      final panel = tester.getRect(find.byType(CookieConsentPanel));
      expect(navigation.bottom, lessThanOrEqualTo(panel.top));
      await tester.ensureVisible(find.text('Reject optional'));
      await tester.tap(find.text('Reject optional'));
      expect(rejected, 1);
      await tester.ensureVisible(find.text('Accept all'));
      expect(tester.getRect(find.text('Accept all')).right,
          lessThanOrEqualTo(size.width));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('equal actions, keyboard order and screen reader labels',
      (tester) async {
    final semantics = tester.ensureSemantics();

    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CookieConsentPanel(
      onReject: () => actions.add('reject'),
      onCustomise: () => actions.add('customise'),
      onAccept: () => actions.add('accept'),
    ))));
    expect(find.text('Your privacy matters.'), findsOneWidget);
    expect(find.text(CookieConsentPanel.message), findsOneWidget);
    final buttons =
        tester.widgetList<OutlinedButton>(find.byType(OutlinedButton)).toList();
    expect(buttons.length, 3);
    expect(buttons[0].style, same(buttons[2].style));
    expect(
        tester.getSize(find.widgetWithText(OutlinedButton, 'Reject optional')),
        tester.getSize(find.widgetWithText(OutlinedButton, 'Accept all')));
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }
    expect(actions, ['reject', 'customise', 'accept']);
    expect(tester.getSemantics(find.text('Reject optional')).label,
        contains('Reject optional'));
    semantics.dispose();
  });
}
