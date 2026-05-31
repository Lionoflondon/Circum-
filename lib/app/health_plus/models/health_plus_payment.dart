class HealthPlusPayment {
  final String id;
  final String profileId;
  final String pickupId;
  final double amount;
  final String currency;
  final String status;
  final String checkoutSessionId;
  final bool savedPaymentMethod;
  final DateTime createdAt;

  const HealthPlusPayment({
    required this.id,
    required this.profileId,
    required this.pickupId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.checkoutSessionId,
    required this.savedPaymentMethod,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'profileId': profileId,
        'pickupId': pickupId,
        'amount': amount,
        'currency': currency,
        'status': status,
        'checkoutSessionId': checkoutSessionId,
        'savedPaymentMethod': savedPaymentMethod,
        'createdAt': createdAt.toIso8601String(),
      };
}
