import 'package:circum/app/sender_mobile/sender_schedule_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('calendar accepts a date beyond the quick seven-day choices',
      (tester) async {
    final future = DateTime.now().add(const Duration(days: 90));
    final value = '${future.year}-${future.month.toString().padLeft(2, '0')}-'
        '${future.day.toString().padLeft(2, '0')}';
    String? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body:
          SenderScheduleDatePicker(value: value, onChanged: (v) => result = v),
    )));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, value);
  });

  testWidgets('time picker returns canonical 24-hour time', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: SenderScheduleTimePicker(
        label: 'Start time',
        value: '14:30',
        onChanged: (v) => result = v,
      ),
    )));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, '14:30');
  });

  testWidgets('cancelling a picker does not change the saved time',
      (tester) async {
    var result = '09:00';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: SenderScheduleTimePicker(
        label: 'Start time',
        value: result,
        onChanged: (v) => result = v,
      ),
    )));
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, '09:00');
  });
}
