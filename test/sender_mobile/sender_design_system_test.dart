import 'package:circum/app/sender_mobile/design_system/sender_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sender design system owns canonical surface tokens', () {
    expect(AppTokens.background, const Color(0xFF07090F));
    expect(AppTokens.primary, const Color(0xFF3B82F6));
    expect(AppTokens.radius24, 24);
  });

  testWidgets('shared Sender components render as one design language',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AppGlassContainer(
            accent: AppTokens.primary,
            child: Column(
              children: [
                AppToggle(label: 'Alerts', value: true, onChanged: (_) {}),
                AppButton(label: 'Continue', onPressed: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('shared empty state and timeline remain accessible',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AppTimeline(
            children: const [
              AppEmptyState(
                icon: Icons.inbox_outlined,
                title: 'No activity yet',
                body: 'Your Circum activity will appear here.',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('No activity yet'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });
}
