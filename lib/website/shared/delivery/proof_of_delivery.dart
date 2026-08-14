import 'package:cloud_firestore/cloud_firestore.dart';

class ProofOfDeliveryDetails {
  final String photoUrl;
  final String deliveredAt;
  final String riderName;
  final String receiverName;
  final String receiverConfirmationMethod;
  final String pinVerificationResult;
  final String gpsConfirmation;
  final String finalAddress;
  final String deliveryReference;
  final bool collectionPinVerified;
  final bool deliveryPinVerified;
  final bool underReview;
  final bool vanguard;

  const ProofOfDeliveryDetails({
    required this.photoUrl,
    required this.deliveredAt,
    required this.riderName,
    required this.receiverName,
    required this.receiverConfirmationMethod,
    required this.pinVerificationResult,
    required this.gpsConfirmation,
    required this.finalAddress,
    required this.deliveryReference,
    required this.collectionPinVerified,
    required this.deliveryPinVerified,
    required this.underReview,
    required this.vanguard,
  });

  bool get hasPhoto => photoUrl.trim().isNotEmpty;

  bool get hasAnyProof =>
      hasPhoto ||
      deliveredAt.trim().isNotEmpty ||
      receiverConfirmationMethod.trim().isNotEmpty ||
      pinVerificationResult.trim().isNotEmpty ||
      gpsConfirmation.trim().isNotEmpty ||
      collectionPinVerified ||
      deliveryPinVerified;

  String get statusLabel {
    if (underReview) return 'Under review';
    return hasAnyProof ? 'Proof available' : 'Proof missing';
  }

  bool get vanguardIncomplete =>
      vanguard &&
      (!collectionPinVerified || !deliveryPinVerified || !hasAnyProof);

  List<(String, String)> get visibleRows {
    final rows = <(String, String)>[
      if (deliveredAt.trim().isNotEmpty) ('Delivered', deliveredAt),
      if (riderName.trim().isNotEmpty) ('Circum Rider', riderName),
      if (receiverName.trim().isNotEmpty) ('Receiver', receiverName),
      if (receiverConfirmationMethod.trim().isNotEmpty)
        ('Receiver confirmation', receiverConfirmationMethod),
      if (pinVerificationResult.trim().isNotEmpty)
        ('PIN verification', pinVerificationResult),
      if (gpsConfirmation.trim().isNotEmpty)
        ('GPS confirmation', gpsConfirmation),
      if (finalAddress.trim().isNotEmpty) ('Final address', finalAddress),
      if (deliveryReference.trim().isNotEmpty)
        ('Delivery reference', deliveryReference),
    ];
    if (vanguard) {
      rows.insertAll(0, [
        (
          'Collection PIN',
          collectionPinVerified ? 'Verified' : 'Not verified',
        ),
        (
          'Delivery PIN',
          deliveryPinVerified ? 'Verified' : 'Not verified',
        ),
      ]);
    }
    return rows;
  }
}

ProofOfDeliveryDetails proofOfDeliveryFromRecord(
  Map<String, dynamic> record, {
  String? fallbackReference,
}) {
  final proof = _firstMap(record, const [
    'proofOfDelivery',
    'deliveryProof',
    'proof',
    'completionProof',
    'deliveryConfirmation',
  ]);
  final vanguard = _isTruthy(record['vanguardEnabled']) ||
      _isTruthy(record['vanguardProtected']) ||
      _isTruthy(record['vanguardProtection']) ||
      _isTruthy(record['vanguard']);
  final collectionPinVerified = _firstBool(record, proof, const [
    'collectionPinVerified',
    'pickupPinVerified',
    'collectionOtpVerified',
    'pickupOtpVerified',
    'vanguardCollectionPinVerified',
  ]);
  final deliveryPinVerified = _firstBool(record, proof, const [
    'deliveryPinVerified',
    'receiverPinVerified',
    'recipientPinVerified',
    'dropoffPinVerified',
    'deliveryOtpVerified',
    'vanguardDeliveryPinVerified',
  ]);
  final gpsConfirmed = _firstBool(record, proof, const [
    'gpsConfirmed',
    'deliveryGpsConfirmed',
    'finalGpsConfirmed',
    'locationConfirmed',
  ]);
  final confirmationMethod = _firstString(record, proof, const [
    'receiverConfirmationMethod',
    'confirmationMethod',
    'handoverMethod',
    'completionMethod',
  ]);
  final pinText = _firstString(record, proof, const [
    'pinVerificationResult',
    'otpVerificationResult',
    'verificationResult',
  ]);
  final deliveryReference = _firstString(record, proof, const [
    'deliveryReference',
    'trackingReference',
  ]);
  return ProofOfDeliveryDetails(
    photoUrl: _proofPhotoUrl(record, proof),
    deliveredAt: _formatDate(_firstValue(record, proof, const [
      'deliveredAt',
      'completedAt',
      'deliveryCompletedAt',
      'timestamp',
      'createdAt',
    ])),
    riderName: _firstString(record, proof, const [
      'riderName',
      'driverName',
      'courierName',
    ]),
    receiverName: _firstString(record, proof, const [
      'receiverName',
      'recipientName',
      'dropoffContactName',
    ]),
    receiverConfirmationMethod: confirmationMethod.isNotEmpty
        ? confirmationMethod
        : deliveryPinVerified
            ? 'PIN verified'
            : gpsConfirmed
                ? 'GPS confirmed'
                : '',
    pinVerificationResult: pinText.isNotEmpty
        ? pinText
        : deliveryPinVerified
            ? 'Verified'
            : '',
    gpsConfirmation: gpsConfirmed ? 'Confirmed at delivery location' : '',
    finalAddress: _firstString(record, proof, const [
      'finalAddress',
      'deliveryAddress',
      'dropoffAddress',
      'destinationAddress',
      'recipientAddress',
    ]),
    deliveryReference: deliveryReference.isNotEmpty
        ? customerFacingDeliveryReference(deliveryReference)
        : customerFacingDeliveryReference(fallbackReference ?? ''),
    collectionPinVerified: collectionPinVerified,
    deliveryPinVerified: deliveryPinVerified,
    underReview: _isUnderReview(record, proof),
    vanguard: vanguard,
  );
}

String customerFacingDeliveryReference(String reference) {
  final value = reference.trim();
  if (value.isEmpty) return '';
  final normalized = value.toLowerCase();
  final compact = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  final suffix = compact.length <= 6
      ? compact.toUpperCase()
      : compact.substring(compact.length - 6).toUpperCase();
  if (normalized.startsWith('gift_')) return 'Gift #$suffix';
  if (normalized.startsWith('health_')) return 'Health+ #$suffix';
  if (normalized.contains('_') || compact.length > 18) {
    return 'Delivery #$suffix';
  }
  return value;
}

String _proofPhotoUrl(Map<String, dynamic> record, Map<String, dynamic> proof) {
  final proofScoped = _firstString(
      const <String, dynamic>{},
      proof,
      const [
        'proofPhotoUrl',
        'deliveryProofPhotoUrl',
        'deliveryPhotoUrl',
        'deliveredPhotoUrl',
        'imageUrl',
        'photoUrl',
      ]);
  if (proofScoped.isNotEmpty) return proofScoped;
  return _firstString(record, const <String, dynamic>{}, const [
    'proofPhotoUrl',
    'deliveryProofPhotoUrl',
    'deliveryPhotoUrl',
    'deliveredPhotoUrl',
  ]);
}

Map<String, dynamic> _firstMap(Map<String, dynamic> record, List<String> keys) {
  for (final key in keys) {
    final value = record[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
  }
  return const {};
}

Object? _firstValue(
  Map<String, dynamic> record,
  Map<String, dynamic> proof,
  List<String> keys,
) {
  for (final key in keys) {
    if (proof.containsKey(key) && '${proof[key]}'.trim().isNotEmpty) {
      return proof[key];
    }
    if (record.containsKey(key) && '${record[key]}'.trim().isNotEmpty) {
      return record[key];
    }
  }
  return null;
}

String _firstString(
  Map<String, dynamic> record,
  Map<String, dynamic> proof,
  List<String> keys,
) {
  final value = _firstValue(record, proof, keys);
  if (value == null) return '';
  return '$value'.trim();
}

bool _firstBool(
  Map<String, dynamic> record,
  Map<String, dynamic> proof,
  List<String> keys,
) {
  for (final key in keys) {
    if (proof.containsKey(key) && _isTruthy(proof[key])) return true;
    if (record.containsKey(key) && _isTruthy(record[key])) return true;
  }
  return false;
}

bool _isTruthy(Object? value) {
  if (value is bool) return value;
  if (value is Map) {
    return value['enabled'] == true ||
        value['verified'] == true ||
        value['protected'] == true ||
        '${value['status'] ?? ''}'.toLowerCase().contains('enabled');
  }
  final text = '$value'.trim().toLowerCase();
  return text == 'true' || text == 'verified' || text == 'confirmed';
}

bool _isUnderReview(Map<String, dynamic> record, Map<String, dynamic> proof) {
  final text = [
    proof['status'],
    proof['reviewStatus'],
    record['proofStatus'],
    record['proofOfDeliveryStatus'],
    record['proofReviewStatus'],
    record['deliveryProofStatus'],
    record['adminProofReviewStatus'],
  ].join(' ').toLowerCase();
  return text.contains('review') || text.contains('dispute');
}

String _formatDate(Object? value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (value is int) date = DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) date = DateTime.tryParse(value);
  if (date == null) return '';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month/${date.year} $hour:$minute';
}
