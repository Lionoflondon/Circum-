class UkPhoneNumber {
  static String? normalizeToE164(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    final compact = raw.replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+?\d+$').hasMatch(compact)) return null;

    final digits = compact.startsWith('+') ? compact.substring(1) : compact;
    if (digits.startsWith('447') && digits.length == 12) {
      return '+$digits';
    }
    if (digits.startsWith('07') && digits.length == 11) {
      return '+44${digits.substring(1)}';
    }
    if (digits.startsWith('7') && digits.length == 10) {
      return '+44$digits';
    }
    return null;
  }
}
