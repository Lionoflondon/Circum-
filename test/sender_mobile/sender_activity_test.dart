import 'dart:async';

import 'package:circum/app/sender_mobile/sender_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeActivityRepository implements SenderActivityRepository {
  final StreamController<List<SenderActivityItem>> active =
      StreamController<List<SenderActivityItem>>.broadcast();
  final List<SenderActivityPage> pages;
  int calls = 0;

  _FakeActivityRepository(this.pages);

  @override
  Future<SenderActivityPage> history({String? pageToken}) async {
    final index = calls++;
    return index < pages.length
        ? pages[index]
        : const SenderActivityPage([], null);
  }

  @override
  Stream<List<SenderActivityItem>> watchActive() => active.stream;
}

Widget _app(SenderActivityRepository repository,
    {VoidCallback? onSend, VoidCallback? onGifts}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      backgroundColor: const Color(0xFF07090F),
      body: SenderActivityView(
        repository: repository,
        onSendParcel: onSend ?? () {},
        onExploreGifts: onGifts ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('empty state offers Sender and Gifts journeys', (tester) async {
    var sent = false;
    var gifts = false;
    final repository = _FakeActivityRepository(
      const [SenderActivityPage([], null)],
    );
    await tester.pumpWidget(_app(
      repository,
      onSend: () => sent = true,
      onGifts: () => gifts = true,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No activity yet'), findsOneWidget);
    expect(
      find.text(
          'Your deliveries, gifts, Health+ requests and business activity will appear here.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Send a Parcel'));
    await tester.tap(find.text('Explore Gifts'));
    expect(sent, isTrue);
    expect(gifts, isTrue);
  });

  testWidgets('live delivery appears automatically with tracking actions',
      (tester) async {
    final repository = _FakeActivityRepository(
      const [SenderActivityPage([], null)],
    );
    await tester.pumpWidget(_app(repository));
    repository.active.add([
      SenderActivityItem(
        id: 'delivery-1',
        type: SenderActivityType.parcel,
        title: 'Passport',
        status: 'In Transit',
        destination: '10 Downing Street',
        pickup: 'Heathrow Airport',
        rider: 'Alex',
        eta: '12 min',
        occurredAt: DateTime.now(),
        active: true,
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Live Activity'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('12 min'), findsOneWidget);
    expect(find.text('Live Tracking'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
  });

  testWidgets('history supports filters, search and pagination',
      (tester) async {
    final now = DateTime.now();
    final repository = _FakeActivityRepository([
      SenderActivityPage([
        SenderActivityItem(
          id: 'parcel-1',
          type: SenderActivityType.parcel,
          title: 'Parcel delivery',
          status: 'Delivered',
          destination: 'Canary Wharf',
          amount: 16.49,
          occurredAt: now,
        ),
        SenderActivityItem(
          id: 'gift-1',
          type: SenderActivityType.gift,
          title: 'Birthday gift',
          status: 'Completed',
          destination: 'Maya',
          occurredAt: now.subtract(const Duration(days: 1)),
        ),
        SenderActivityItem(
          id: 'roth-1',
          type: SenderActivityType.roth,
          title: 'Referral reward',
          status: 'Completed',
          destination: '',
          rothAmount: 5,
          rothDirection: 'credit',
          occurredAt: now.subtract(const Duration(days: 3)),
        ),
      ], '1'),
      SenderActivityPage([
        SenderActivityItem(
          id: 'health-1',
          type: SenderActivityType.health,
          title: 'Health+ request',
          status: 'Delivered',
          destination: 'Home',
          occurredAt: now.subtract(const Duration(days: 10)),
        ),
      ], null),
    ]);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('This Week'), findsOneWidget);

    await tester.tap(find.text('Gifts'));
    await tester.pump();
    expect(find.text('Birthday gift'), findsOneWidget);
    expect(find.text('Parcel delivery'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.enterText(find.byType(TextField), 'Canary Wharf');
    await tester.pump();
    expect(find.text('Parcel delivery'), findsOneWidget);
    expect(find.text('Birthday gift'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.scrollUntilVisible(find.text('Load more activity'), 120,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Load more activity'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Health+ request'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Health+ request'), findsOneWidget);
  });
}
