class GiftRequestPolicy {
  static const double minimumBudget = 50;
  static const String privatePreviewEmail = 'ayojason600@gmail.com';

  static bool canAccessPrivatePreview(String? email) {
    return email?.trim().toLowerCase() == privatePreviewEmail;
  }

  static double estimatedNetGiftBudget(double grossBudget) {
    if (grossBudget <= 0) return 0;
    return grossBudget * 0.70;
  }

  static String? validate({
    required String senderEmail,
    required String recipientName,
    required String relationship,
    required String occasion,
    required String deliveryAddress,
    required DateTime? deliveryDate,
    required double? grossBudget,
  }) {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(senderEmail.trim())) {
      return 'Enter a valid sender email address.';
    }
    if (recipientName.trim().isEmpty) return 'Enter the recipient name.';
    if (relationship.trim().isEmpty) return 'Select a relationship.';
    if (occasion.trim().isEmpty) return 'Select an occasion.';
    if (deliveryAddress.trim().isEmpty) return 'Enter the delivery address.';
    if (deliveryDate == null) return 'Select a preferred delivery date.';
    if (grossBudget == null || grossBudget < minimumBudget) {
      return 'Gift budgets start from £50.';
    }
    return null;
  }

  static String senderStatus(String status) {
    return switch (status.trim().toLowerCase()) {
      'submitted' || 'draft' => 'Request submitted',
      'reviewing' => 'Under review',
      'approved' => 'Approved',
      'procuring' || 'packed' => 'Being prepared',
      'out_for_delivery' => 'Out for delivery',
      'delivered' => 'Delivered',
      'cancelled' => 'Cancelled',
      _ => 'Request submitted',
    };
  }
}
