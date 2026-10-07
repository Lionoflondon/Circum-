import 'dart:convert';

const agentBookingDraftStorageKey = 'circum.agentBookingDraft.v1';
const agentBookingDraftLifetime = Duration(minutes: 15);

/// Untrusted preparation data. It carries no address, price or payment approval.
class AgentBookingDraft {
  const AgentBookingDraft(this.details);
  final Map<String, dynamic> details;

  static AgentBookingDraft? parse(String raw, DateTime now) {
    if (raw.length > 10000) return null;
    try {
      final envelope = jsonDecode(raw);
      if (envelope is! Map ||
          envelope['version'] != 1 ||
          envelope['status'] != 'customer_review_required')
        return null;
      final created = envelope['createdAt'];
      final expires = envelope['expiresAt'];
      final timestamp = now.millisecondsSinceEpoch;
      if (created is! int ||
          expires is! int ||
          created > timestamp ||
          expires <= timestamp ||
          expires - created != agentBookingDraftLifetime.inMilliseconds)
        return null;
      final details = envelope['details'];
      if (details is! Map) return null;
      const limits = {
        'pickup': 500,
        'dropoff': 500,
        'description': 2000,
        'receiverName': 120,
        'receiverPhone': 40,
      };
      if (details.keys.any(
        (key) => !limits.containsKey(key) && key != 'weightKg',
      ))
        return null;
      final clean = <String, dynamic>{};
      for (final entry in limits.entries) {
        final value = details[entry.key];
        final required = [
          'pickup',
          'dropoff',
          'description',
        ].contains(entry.key);
        if (value == null && !required) continue;
        if (value is! String ||
            value.trim().length > entry.value ||
            (required && value.trim().length < 3) ||
            RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(value))
          return null;
        clean[entry.key] = value.trim();
      }
      final weight = details['weightKg'];
      if (weight != null) {
        if (weight is! num || !weight.isFinite || weight <= 0 || weight > 200)
          return null;
        clean['weightKg'] = weight.toDouble();
      }
      return AgentBookingDraft(Map.unmodifiable(clean));
    } catch (_) {
      return null;
    }
  }
}
