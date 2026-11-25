import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circum/website/shared/rider_order_explainer.dart';

void main() {
  testWidgets('public explainer describes every rank before account access',
      (tester) async {
    var login = false;
    var join = false;
    await tester.pumpWidget(MaterialApp(
        home: RiderOrderExplainer(
            onBack: () {},
            onLogin: () => login = true,
            onJoin: () => join = true)));
    expect(find.text('Every Veteran\nwas once an Agent.'), findsOneWidget);
    for (var i = 0; i < RiderOrderExplainer.ranks.length; i++) {
      final label = '0${i + 1} / ${RiderOrderExplainer.ranks[i].$1}';
      await tester.scrollUntilVisible(find.text(label), 400);
      expect(find.text(label), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Join Circum Riders'), 400);
    await tester.ensureVisible(find.text('Join Circum Riders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join Circum Riders'));
    await tester.tap(find.text('Rider login'));
    expect(join, isTrue);
    expect(login, isTrue);
  });
}
