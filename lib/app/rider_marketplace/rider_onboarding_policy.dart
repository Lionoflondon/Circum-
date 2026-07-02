class RiderOnboardingPolicy {
  static const superAdminEmail = 'ayojason600@gmail.com';

  static bool isSuperAdmin(String? email) =>
      email?.trim().toLowerCase() == superAdminEmail;

  static String status(Map<String, dynamic>? profile) {
    if (profile == null) return 'not_started';
    final legacy =
        '${profile['approvalStatus'] ?? profile['verificationStatus'] ?? ''}'
            .trim()
            .toLowerCase();
    if (legacy == 'suspended') return 'suspended';
    final onboarding =
        '${profile['onboardingStatus'] ?? ''}'.trim().toLowerCase();
    if (const {
      'not_started',
      'pending_review',
      'approved',
      'rejected',
    }.contains(onboarding)) {
      return onboarding;
    }

    return switch (legacy) {
      'approved' || 'verified' => 'approved',
      'rejected' => 'rejected',
      'pending' => 'pending_review',
      _ => 'not_started',
    };
  }

  static bool isApproved({
    required String? email,
    Map<String, dynamic>? profile,
    bool verifiedSuperAdmin = false,
  }) {
    return (verifiedSuperAdmin && isSuperAdmin(email)) ||
        status(profile) == 'approved';
  }

  static bool canViewJobs({
    required String? email,
    Map<String, dynamic>? profile,
    bool verifiedSuperAdmin = false,
  }) =>
      isApproved(
        email: email,
        profile: profile,
        verifiedSuperAdmin: verifiedSuperAdmin,
      );

  static bool canAcceptJobs({
    required String? email,
    Map<String, dynamic>? profile,
    bool verifiedSuperAdmin = false,
  }) =>
      canViewJobs(
        email: email,
        profile: profile,
        verifiedSuperAdmin: verifiedSuperAdmin,
      );

  static bool canWithdraw({
    required String? email,
    Map<String, dynamic>? profile,
    bool verifiedSuperAdmin = false,
  }) =>
      (verifiedSuperAdmin && isSuperAdmin(email)) ||
      (isApproved(email: email, profile: profile) &&
          '${profile?['stripeAccountId'] ?? profile?['stripeConnectAccountId'] ?? ''}'
              .trim()
              .isNotEmpty &&
          (profile?['stripeOnboardingStatus'] == 'complete' ||
              profile?['onboardingComplete'] == true) &&
          (profile?['stripePayoutsEnabled'] == true ||
              profile?['payoutsEnabled'] == true) &&
          profile?['payoutPaused'] != true);

  static Map<String, dynamic> adminReviewPatch({
    required bool approved,
    String rejectionReason = '',
  }) {
    if (!approved && rejectionReason.trim().isEmpty) {
      throw ArgumentError('A rejection reason is required.');
    }
    return {
      'onboardingStatus': approved ? 'approved' : 'rejected',
      'approvalStatus': approved ? 'approved' : 'rejected',
      'verificationStatus': approved ? 'approved' : 'rejected',
      if (approved) 'riderRank': 'agent',
      if (!approved) 'rejectionReason': rejectionReason.trim(),
    };
  }
}
