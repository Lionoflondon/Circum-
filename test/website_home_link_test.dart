import 'dart:ui' show SemanticsAction;
import 'package:circum/website/shared/circum_home_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('brand activation opens home with pointer and keyboard',
      (tester) async {
    final launches = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'launch') {
        final arguments = call.arguments as Map;
        expect(arguments['webOnlyWindowName'], '_self');
        launches.add(arguments['url'] as String);
        return true;
      }
      return false;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CircumHomeLink(child: Text('CIRCUM')),
      ),
    ));
    expect(find.bySemanticsLabel('CIRCUM home'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(launches, ['https://circumuk.com/']);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(launches, ['https://circumuk.com/', 'https://circumuk.com/']);
    tester.binding.pipelineOwner.semanticsOwner!.performAction(
        tester.getSemantics(find.bySemanticsLabel('CIRCUM home')).id,
        SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(launches.length, 3);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
