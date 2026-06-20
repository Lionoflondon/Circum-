class HealthPlusCustodyEvent {
  final String eventType;
  final DateTime timestamp;
  final String actorType;
  final String? actorId;
  final String? actorName;
  final String publicMessage;
  final String? internalNote;
  final String? evidenceUrl;
  final String statusAfterEvent;

  const HealthPlusCustodyEvent({
    required this.eventType,
    required this.timestamp,
    required this.actorType,
    required this.publicMessage,
    required this.statusAfterEvent,
    this.actorId,
    this.actorName,
    this.internalNote,
    this.evidenceUrl,
  });

  Map<String, dynamic> toJson() => {
        'eventType': eventType,
        'timestamp': timestamp.toIso8601String(),
        'actorType': actorType,
        'actorId': actorId,
        'actorName': actorName,
        'publicMessage': publicMessage,
        'internalNote': internalNote,
        'evidenceUrl': evidenceUrl,
        'statusAfterEvent': statusAfterEvent,
      };
}
