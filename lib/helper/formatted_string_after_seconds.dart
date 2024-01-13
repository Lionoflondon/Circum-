import 'package:intl/intl.dart';

String formattedTimeAfterSeconds(int secondsToAdd) {
  // Get the current date and time
  DateTime now = DateTime.now();

  // Add seconds to the current date and time
  DateTime futureTime = now.add(Duration(seconds: secondsToAdd));

  // Format the resulting time into 'hh:mm a' format (12-hour clock with AM/PM)
  String formattedTime = DateFormat('h:mm a').format(futureTime);

  return formattedTime;
}
