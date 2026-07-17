import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../utils/theme/theme.dart';

class WalletView extends StatelessWidget {
  const WalletView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _appBar(context),
          const SizedBox(height: 28),
          _walletSummary(context),
          const SizedBox(height: 24),
          _walletDetails(),
        ],
      ),
    );
  }

  Widget _appBar(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        left: 24,
        right: 24,
      ),
      width: double.infinity,
      child: AppText.text(
        'Wallet',
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _walletSummary(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SvgPicture.asset(
                  'assets/svg/wallet.svg',
                  height: 28,
                  colorFilter: const ColorFilter.mode(
                      AppColors.primary, BlendMode.srcIn),
                ),
                const SizedBox(width: 12),
                AppText.text(
                  'Circum Wallet',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppText.text(
              'Payment methods, Roth balance and delivery receipts stay controlled by Circum payment services.',
              color: AppColors.textGrey,
              fontSize: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletDetails() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _walletInfoCard(
            icon: 'assets/svg/wallet.svg',
            title: 'Payment methods',
            subtitle:
                'Cards, Apple Pay and Google Pay are handled during secure checkout.',
          ),
          const SizedBox(height: 12),
          _walletInfoCard(
            icon: 'assets/svg/delivery_history.svg',
            title: 'Receipts',
            subtitle:
                'Paid deliveries and receipts remain visible in Activity.',
          ),
        ],
      ),
    );
  }

  Widget _walletInfoCard({
    required String icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.input.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            icon,
            height: 24,
            colorFilter:
                const ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.text(title, fontWeight: FontWeight.w600),
                const SizedBox(height: 4),
                AppText.text(
                  subtitle,
                  color: AppColors.textGrey,
                  fontSize: 12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
