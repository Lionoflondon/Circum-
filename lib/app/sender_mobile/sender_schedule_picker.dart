import 'package:flutter/material.dart';

import 'sender_booking_state.dart';

class SenderScheduleDatePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const SenderScheduleDatePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        icon: const Icon(Icons.calendar_month),
        label: Text(value.isEmpty ? 'Choose a future date' : 'Date: $value'),
        onPressed: () async {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final selected = DateTime.tryParse(value);
          final date = await showDatePicker(
            context: context,
            initialDate: selected != null && !selected.isBefore(today)
                ? selected
                : today,
            firstDate: today,
            lastDate: DateTime(9999, 12, 31),
            helpText: 'Choose collection date',
          );
          if (date != null) onChanged(senderScheduleDateValue(date));
        },
      );
}

class SenderScheduleTimePicker extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const SenderScheduleTimePicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        icon: const Icon(Icons.schedule),
        label: Text(value.isEmpty ? label : '$label: $value'),
        onPressed: () async {
          final parts = value.split(':');
          final hour = parts.length == 2 ? int.tryParse(parts[0]) : null;
          final minute = parts.length == 2 ? int.tryParse(parts[1]) : null;
          final time = await showTimePicker(
            context: context,
            initialTime: hour != null &&
                    minute != null &&
                    hour >= 0 &&
                    hour < 24 &&
                    minute >= 0 &&
                    minute < 60
                ? TimeOfDay(hour: hour, minute: minute)
                : TimeOfDay.now(),
            helpText: label,
            builder: (context, child) => MediaQuery(
              data:
                  MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
          );
          if (time != null) {
            onChanged('${time.hour.toString().padLeft(2, '0')}:'
                '${time.minute.toString().padLeft(2, '0')}');
          }
        },
      );
}
