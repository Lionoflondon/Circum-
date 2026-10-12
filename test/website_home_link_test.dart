import 'package:circum/website/shared/circum_home_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/link.dart';

void main() {
  testWidgets('brand activation opens home with pointer and keyboard',
      (tester) async {
    final launches = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'launch') {
        launches.add((call.arguments as Map)['url'] as String);
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
    expect(tester.widget<Link>(find.byType(Link)).target, LinkTarget.self);
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
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
