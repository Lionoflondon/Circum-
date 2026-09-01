String normalizeSenderFirstName(String value) => value.trim();

String senderGreetingForLocalTime(DateTime localTime) {
  final hour = localTime.hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String senderGreeting({
  required DateTime localTime,
  required String firstName,
}) {
  final greeting = senderGreetingForLocalTime(localTime);
  final normalizedName = normalizeSenderFirstName(firstName);
  return normalizedName.isEmpty ? greeting : '$greeting, $normalizedName';
}
