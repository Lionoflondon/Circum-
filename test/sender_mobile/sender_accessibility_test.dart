import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:circum/app/sender_mobile/sender_accessibility.dart';

class _MemoryAccessibilityRepository implements SenderAccessibilityRepository {
  final _stream = StreamController<SenderAccessibilitySettings>.broadcast();
  SenderAccessibilitySettings value;
  int saves = 0;

  _MemoryAccessibilityRepository([
    this.value = const SenderAccessibilitySettings(),
  ]);

  @override
  Stream<SenderAccessibilitySettings> watch() async* {
    yield value;
    yield* _stream.stream;
  }

  @override
  Future<void> save(SenderAccessibilitySettings settings) async {
    value = settings;
    saves++;
    _stream.add(settings);
  }

  Future<void> close() => _stream.close();
}

void main() {
  test('settings serialize every persisted preference', () {
    const settings = SenderAccessibilitySettings(
      textSize: SenderTextSize.extraLarge,
      highContrast: true,
      reduceMotion: true,
      largerTouchTargets: true,
      hapticFeedback: false,
      confirmBeforePayment: true,
      voiceGuidance: true,
      readNotifications: true,
      deliveryAlerts: SenderDeliveryAlertLevel.persistent,
      announceRiderArrival: false,
      announceDeliveryComplete: false,
      colourVisionMode: SenderColourVisionMode.tritanopia,
      flashDeliveryAlerts: true,
      leftHandedMode: true,
    );

    expect(SenderAccessibilitySettings.fromMap(settings.toMap()).toMap(),
        settings.toMap());
  });

  testWidgets('settings screen updates and persists immediately',
      (tester) async {
    final repository = _MemoryAccessibilityRepository();
    final controller = SenderAccessibilityController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SenderAccessibilityHost(
          controller: controller,
          child: const SenderAccessibilityView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('High contrast'));
    await tester.pumpAndSettle();

    expect(repository.value.highContrast, isTrue);
    expect(repository.saves, 1);
  });

  testWidgets('text size rebuilds the Sender subtree', (tester) async {
    final repository = _MemoryAccessibilityRepository(
      const SenderAccessibilitySettings(textSize: SenderTextSize.extraLarge),
    );
    final controller = SenderAccessibilityController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SenderAccessibilityHost(
          controller: controller,
          child: Builder(
            builder: (context) => Text(
              '${MediaQuery.textScalerOf(context).scale(10)}',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('13.0'), findsOneWidget);
  });

  testWidgets('high contrast applies the dedicated Sender contrast theme',
      (tester) async {
    final repository = _MemoryAccessibilityRepository(
      const SenderAccessibilitySettings(highContrast: true),
    );
    final controller = SenderAccessibilityController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });
    ThemeData? theme;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SenderAccessibilityHost(
          controller: controller,
          child: Builder(
            builder: (context) {
              theme = Theme.of(context);
              return const Card(child: Text('Contrast ready'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(theme!.colorScheme.primary, const Color(0xFF168BFF));
    expect(theme!.colorScheme.onSurface, Colors.white);
    expect(theme!.textTheme.bodyMedium!.color, const Color(0xFFE5E7EB));
    expect(theme!.cardTheme.color, const Color(0xFA0C121C));
    expect(theme!.cardTheme.shape, isA<RoundedRectangleBorder>());
  });

  testWidgets('confirm-before-payment gates every payment method',
      (tester) async {
    final repository = _MemoryAccessibilityRepository(
      const SenderAccessibilitySettings(confirmBeforePayment: true),
    );
    final controller = SenderAccessibilityController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });
    var result = false;

    await tester.pumpWidget(
      MaterialApp(
        home: SenderAccessibilityHost(
          controller: controller,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await confirmSenderPaymentIfRequired(
                  context,
                  paymentMethod: 'Apple Pay',
                  amount: '£12.00',
                );
              },
              child: const Text('Pay'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();

    expect(find.text('Charge £12.00 using Apple Pay?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm payment'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('reset restores defaults after confirmation', (tester) async {
    final repository = _MemoryAccessibilityRepository(
      const SenderAccessibilitySettings(
        highContrast: true,
        voiceGuidance: true,
      ),
    );
    final controller = SenderAccessibilityController(repository: repository);
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SenderAccessibilityHost(
          controller: controller,
          child: const SenderAccessibilityView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Reset accessibility settings'),
      400,
    );
    await tester.tap(find.text('Reset accessibility settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(
        repository.value.toMap(), const SenderAccessibilitySettings().toMap());
  });
}
