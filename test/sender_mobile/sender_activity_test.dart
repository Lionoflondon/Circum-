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
    home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Scaffold(
        backgroundColor: const Color(0xFF07090F),
        body: SenderActivityView(
          repository: repository,
          onSendParcel: onSend ?? () {},
          onExploreGifts: onGifts ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('empty live state offers the Sender journey', (tester) async {
    var sent = false;
    final repository = _FakeActivityRepository(
      const [SenderActivityPage([], null)],
    );
    await tester.pumpWidget(_app(
      repository,
      onSend: () => sent = true,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No live deliveries'), findsOneWidget);
    expect(
      find.text(
          "When you send a parcel, gift or Health+ request, you'll be able to track it here."),
      findsOneWidget,
    );
    await tester.tap(find.text('Send a Parcel'));
    expect(sent, isTrue);
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
          rider: 'Sarah',
          riderRank: 'Knight',
          riderRating: 4.98,
          trustPoints: 5,
          vanguardProtected: true,
          irisVerified: true,
          riderTrusted: true,
          riderCompletedDeliveries: 124,
          riderMemberSince: DateTime(2024, 2, 1),
          riderAchievements: const ['Consistent service'],
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

    await tester.scrollUntilVisible(
      find.text('Today'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Delivered Successfully'), findsOneWidget);
    expect(find.text('Sarah'), findsOneWidget);
    expect(find.text('Knight'), findsOneWidget);
    expect(find.text('4.98'), findsOneWidget);
    expect(find.text('+5 Trust Points'), findsOneWidget);
    expect(find.text('Vanguard Protected'), findsOneWidget);
    expect(find.text('IRIS Verified'), findsOneWidget);
    expect(find.text('View Receipt'), findsOneWidget);
    await tester.ensureVisible(find.text('Sarah'));
    await tester.pump();
    await tester.tap(find.text('Sarah'));
    await tester.pumpAndSettle();
    expect(find.text('Completed deliveries'), findsOneWidget);
    expect(find.text('124'), findsOneWidget);
    expect(find.text('Consistent service'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Yesterday'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Yesterday'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Earlier'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Earlier'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Gifts'),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Gifts'));
    await tester.pump();
    expect(find.text('Birthday gift'), findsOneWidget);
    expect(find.text('Parcel delivery'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), 'Canary Wharf');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Parcel delivery'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Parcel delivery'), findsOneWidget);
    expect(find.text('Birthday gift'), findsNothing);

    await tester.scrollUntilVisible(
      find.byType(TextField),
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), '');
    final loadMore = find.widgetWithText(TextButton, 'Load more activity');
    await tester.scrollUntilVisible(
      loadMore,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(loadMore);
    await tester.pump();
    await tester.tap(loadMore);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Health+ request'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Health+ request'), findsOneWidget);
  });

  test('canonical delivery state decides Live Activity membership', () {
    for (final status in [
      'finding_rider',
      'broadcasting',
      'rider_assigned',
      'rider_en_route',
      'arriving_at_pickup',
      'picked_up',
      'in_transit',
      'arriving_at_dropoff',
      'waiting_for_recipient',
      'delivery_confirmation',
    ]) {
      expect(senderActivityIsLiveDeliveryStatus(status), isTrue,
          reason: status);
    }
    for (final status in [
      'completed',
      'cancelled',
      'expired',
      'archived_expired',
      'rejected',
      'failed',
    ]) {
      expect(senderActivityIsLiveDeliveryStatus(status), isFalse,
          reason: status);
    }
  });
}
