import 'package:circum/app/delivery/proof_of_delivery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('proofOfDeliveryFromRecord', () {
    test('completed delivery with proof photo exposes proof details', () {
      final proof = proofOfDeliveryFromRecord({
        'requestId': 'DEL-100',
        'riderName': 'Alex Rider',
        'recipientName': 'Maya Receiver',
        'dropoffAddress': '10 Proof Street, London',
        'proofOfDelivery': {
          'photoUrl': 'https://example.com/proof.jpg',
          'deliveredAt': '2026-07-22T14:30:00Z',
          'confirmationMethod': 'Receiver confirmed',
        },
      });

      expect(proof.hasAnyProof, isTrue);
      expect(proof.hasPhoto, isTrue);
      expect(proof.statusLabel, 'Proof available');
      expect(proof.riderName, 'Alex Rider');
      expect(proof.receiverName, 'Maya Receiver');
      expect(proof.finalAddress, '10 Proof Street, London');
    });

    test('completed delivery without photo does not pretend a photo exists',
        () {
      final proof = proofOfDeliveryFromRecord({
        'requestId': 'DEL-101',
        'photoUrl': 'https://example.com/rider-avatar.jpg',
        'completedAt': '2026-07-22T14:30:00Z',
        'deliveryPinVerified': true,
      });

      expect(proof.hasAnyProof, isTrue);
      expect(proof.hasPhoto, isFalse);
      expect(proof.statusLabel, 'Proof available');
      expect(proof.pinVerificationResult, 'Verified');
    });

    test('canonical evidence id is proof without trusting a public URL', () {
      final proof = proofOfDeliveryFromRecord({
        'requestId': 'DEL-104',
        'completedAt': '2026-07-22T14:30:00Z',
        'deliveryEvidence': {
          'completionEvidenceId': 'evidence-104',
          'completionProof': {
            'evidenceId': 'evidence-104',
            'evidenceType': 'completion_proof',
            'lifecycleStage': 'completion',
            'storagePath': 'deliveryEvidence/DEL-104/rider-1/evidence-104.jpg',
            'visibility': 'rider_sender_admin',
            'status': 'finalized',
          },
        },
      });

      expect(proof.hasAnyProof, isTrue);
      expect(proof.hasPhoto, isFalse);
      expect(proof.hasCanonicalEvidence, isTrue);
      expect(proof.requiresAccessToken, isTrue);
      expect(proof.evidenceId, 'evidence-104');
      expect(proof.statusLabel, 'Proof available');
      expect(
          proof.visibleRows, contains(('Evidence reference', 'evidence-104')));
    });

    test('root completion evidence id is also treated as canonical proof', () {
      final proof = proofOfDeliveryFromRecord({
        'requestId': 'DEL-105',
        'completionEvidenceId': 'evidence-105',
        'proofOfDelivery': {
          'evidenceType': 'completion_proof',
          'status': 'finalized',
        },
      });

      expect(proof.hasCanonicalEvidence, isTrue);
      expect(proof.evidenceId, 'evidence-105');
      expect(proof.statusLabel, 'Proof available');
    });

    test('delivery with no evidence is proof missing', () {
      final proof = proofOfDeliveryFromRecord({'requestId': 'DEL-102'});

      expect(proof.hasAnyProof, isFalse);
      expect(proof.hasPhoto, isFalse);
      expect(proof.statusLabel, 'Proof missing');
    });

    test('vanguard delivery with missing PIN evidence is incomplete', () {
      final proof = proofOfDeliveryFromRecord({
        'requestId': 'DEL-103',
        'vanguardEnabled': true,
        'collectionPinVerified': true,
        'completedAt': '2026-07-22T14:30:00Z',
      });

      expect(proof.hasAnyProof, isTrue);
      expect(proof.vanguardIncomplete, isTrue);
      expect(proof.visibleRows, contains(('Collection PIN', 'Verified')));
      expect(proof.visibleRows, contains(('Delivery PIN', 'Not verified')));
    });
  });
}
