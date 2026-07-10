import 'package:circum/app/business/business_iris_moments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical triggers route Health+, Delivery and Gifts separately', () {
    final health = {
      'type': 'Health+ Reminder',
      'preferredAction': 'Schedule Health+ Delivery'
    };
    final delivery = {
      'type': 'Delivery Reminder',
      'preferredAction': 'Create Delivery'
    };
    final gift = {'type': 'Employee Birthday', 'preferredAction': 'Send Gift'};

    expect(momentIsHealth(health), isTrue);
    expect(momentIsDelivery(health), isFalse);
    expect(momentIsDelivery(delivery), isTrue);
    expect(momentIsGiftOpportunity(delivery), isFalse);
    expect(momentIsGiftOpportunity(gift), isTrue);
    expect(
      momentRecommendedService(gift),
      'Launch a Employee Birthday Gift request via the Circum Gift Portal.',
    );
  });

  test('canonical confidence uses history, preference and dismissal signals',
      () {
    final upcoming = {
      'type': 'Birthday',
      'preferredAction': 'Send Gift',
      'status': 'upcoming',
      'eventDate': DateTime.now(),
    };
    final completed = {'type': 'Birthday', 'status': 'completed'};
    final dismissed = {'type': 'Birthday', 'status': 'dismissed'};

    final base = momentRecommendationConfidence(upcoming, [upcoming]);
    final learned = momentRecommendationConfidence(
      upcoming,
      [upcoming, completed],
    );
    final reduced = momentRecommendationConfidence(
      upcoming,
      [upcoming, dismissed],
    );

    expect(learned, greaterThan(base));
    expect(reduced, lessThan(base));
  });

  testWidgets('native panel preserves canonical sequence and copy',
      (tester) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BusinessIrisMomentsPanel(
            businessName: 'Rothcross',
            canOperate: true,
            moments: [
              {
                'name': 'Amara',
                'type': 'Employee Birthday',
                'preferredAction': 'Send Gift',
                'eventDate': tomorrow,
                'status': 'upcoming',
              },
            ],
            onAddMoment: () {},
            onSendGift: () {},
            onCreateDelivery: () {},
            onScheduleHealthPlus: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('IRIS Moments'), findsOneWidget);
    expect(
        find.text('IRIS has reviewed your upcoming moments.'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('This Week'), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);
    expect(find.text('IRIS Recommendations'), findsOneWidget);
    expect(find.text('Relationship Health'), findsOneWidget);
    expect(find.text('Recently Completed'), findsOneWidget);
    expect(find.text('Open Gift Portal'), findsWidgets);
  });

  testWidgets('add dialog uses canonical fields and actions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BusinessMomentDialog()));
    await tester.pumpAndSettle();

    expect(find.text('Add IRIS Moment'), findsOneWidget);
    expect(find.text('Person or company'), findsOneWidget);
    expect(find.text('Relationship optional'), findsOneWidget);
    expect(find.text('Moment type'), findsOneWidget);
    expect(find.text('Preferred action'), findsOneWidget);
    expect(find.text('Add Moment'), findsOneWidget);
  });
}
