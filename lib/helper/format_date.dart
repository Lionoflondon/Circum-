import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

String formatTimestamp(Timestamp timestamp) {
  String originalDateString = '${timestamp.toDate()}';

  // Parsing the original date string
  DateTime originalDate = DateTime.parse(originalDateString);

  // Formatting the date into the desired format
  String formattedDate = DateFormat.yMMMMd().add_jm().format(originalDate);

  return formattedDate; // Output: January 5, 2024 at 5:32 PM
}
