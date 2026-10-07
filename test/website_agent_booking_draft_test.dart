import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:circum/website/shared/agent_booking_draft.dart';

void main() {
  final now = DateTime.utc(2026, 10, 7, 12);
  Map<String, dynamic> envelope(Map<String, dynamic> details) => {
        'version': 1,
        'status': 'customer_review_required',
        'createdAt': now.millisecondsSinceEpoch,
        'expiresAt': now.add(agentBookingDraftLifetime).millisecondsSinceEpoch,
        'details': details,
      };
  const details = {
    'pickup': 'Example collection address',
    'dropoff': 'Example delivery address',
    'description': 'A box of books',
    'weightKg': 2
  };
  test('imports editable parcel details without accepting booking authority',
      () {
    final draft = AgentBookingDraft.parse(jsonEncode(envelope(details)), now);
    expect(draft?.details['weightKg'], 2.0);
    expect(draft?.details['pickup'], details['pickup']);
    expect(
        AgentBookingDraft.parse(
            jsonEncode(envelope({...details, 'paid': true})), now),
        isNull);
    expect(
        AgentBookingDraft.parse(
            jsonEncode(envelope({...details, 'pickupVerified': true})), now),
        isNull);
    expect(
        AgentBookingDraft.parse(
            jsonEncode({...envelope(details), 'status': 'approved'}), now),
        isNull);
  });
  test('fails closed for expired, future and malformed drafts', () {
    expect(
        AgentBookingDraft.parse(
            jsonEncode(envelope(details)), now.add(agentBookingDraftLifetime)),
        isNull);
    expect(
        AgentBookingDraft.parse(jsonEncode(envelope(details)),
            now.subtract(const Duration(seconds: 1))),
        isNull);
    expect(AgentBookingDraft.parse('{', now), isNull);
    expect(
        AgentBookingDraft.parse(
            jsonEncode(envelope({...details, 'weightKg': 201})), now),
        isNull);
    expect(
        AgentBookingDraft.parse(
            jsonEncode(envelope({...details, 'description': '\u0000parcel'})),
            now),
        isNull);
    expect(
        AgentBookingDraft.parse(
            jsonEncode(envelope({...details, 'pickup': 'x' * 501})), now),
        isNull);
  });
}
