import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../utils/theme/theme.dart';
import '../account/view/account.dart';
import '../account/view/wallet.dart';
import '../authentication/bloc/auth_bloc.dart';
import '../health_plus/view/health_plus.dart';
import '../history/view/index.dart';
import '../send_package/view/index.dart';

const senderMobileBottomNavigationLabels = [
  'Home',
  'Send',
  'Activity',
  'Wallet',
  'Profile',
];

class SenderMobileHome extends StatefulWidget {
  const SenderMobileHome({super.key});

  @override
  State<SenderMobileHome> createState() => _SenderMobileHomeState();
}

class _SenderMobileHomeState extends State<SenderMobileHome> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071017),
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            _SenderDashboard(
              onSend: () => _selectTab(1),
              onActivity: () => _selectTab(2),
              onWallet: () => _selectTab(3),
            ),
            const HomeView(),
            const HistoryView(),
            const WalletView(),
            const AccountView(),
          ],
        ),
      ),
      bottomNavigationBar: _SenderBottomNav(
        index: _index,
        onChanged: _selectTab,
      ),
    );
  }

  void _selectTab(int index) {
    setState(() => _index = index);
  }
}

class _SenderDashboard extends StatelessWidget {
  const _SenderDashboard({
    required this.onSend,
    required this.onActivity,
    required this.onWallet,
  });

  final VoidCallback onSend;
  final VoidCallback onActivity;
  final VoidCallback onWallet;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final name = (auth.username ?? '').trim();
    final greeting = name.isEmpty ? 'Hi' : 'Hi ${name.split(' ').first}';

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SenderHeader(auth: auth, onNotifications: onActivity),
                const SizedBox(height: 24),
                _HeroPanel(greeting: greeting, onSend: onSend),
                const SizedBox(height: 18),
                _PremiumServicesRow(
                  onHealth: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const HealthPlusView(),
                    ),
                  ),
                  onBusiness: () => _showUnavailable(
                    context,
                    'Business Centre is available in Sender Web.',
                  ),
                  onGifts: () => _showUnavailable(
                    context,
                    'Gifts remain available from Sender Web.',
                  ),
                ),
                const SizedBox(height: 18),
                _MetricsRow(onActivity: onActivity, onWallet: onWallet),
                const SizedBox(height: 18),
                _NextSteps(onSend: onSend, onActivity: onActivity),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showUnavailable(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF15202B),
      ),
    );
  }
}

class _SenderHeader extends StatelessWidget {
  const _SenderHeader({
    required this.auth,
    required this.onNotifications,
  });

  final AuthState auth;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SvgPicture.asset('assets/svg/logo.svg', width: 106),
        const Spacer(),
        _RoundIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: onNotifications,
        ),
        const SizedBox(width: 10),
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          backgroundImage:
              auth.profilePhoto == null || auth.profilePhoto!.isEmpty
                  ? null
                  : NetworkImage(auth.profilePhoto!),
          child: auth.profilePhoto == null || auth.profilePhoto!.isEmpty
              ? const Icon(Icons.person_outline_rounded, color: Colors.white)
              : null,
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.greeting, required this.onSend});

  final String greeting;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF123D59), Color(0xFF0B1B28)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.18),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Book a parcel, check a past delivery, or update your sender details.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.76),
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onSend,
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: const Text('Send a Parcel'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0B1B28),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumServicesRow extends StatelessWidget {
  const _PremiumServicesRow({
    required this.onHealth,
    required this.onBusiness,
    required this.onGifts,
  });

  final VoidCallback onHealth;
  final VoidCallback onBusiness;
  final VoidCallback onGifts;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ServiceCard(
            icon: Icons.health_and_safety_outlined,
            title: 'Health+',
            tint: const Color(0xFF63F7A6),
            onTap: onHealth,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ServiceCard(
            icon: Icons.business_center_outlined,
            title: 'Business',
            tint: AppColors.primary,
            onTap: onBusiness,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ServiceCard(
            icon: Icons.card_giftcard_rounded,
            title: 'Gifts',
            tint: const Color(0xFFE879F9),
            onTap: onGifts,
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: tint, size: 22),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, color: tint, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.onActivity, required this.onWallet});

  final VoidCallback onActivity;
  final VoidCallback onWallet;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            label: 'Activity',
            value: 'History',
            onTap: onActivity,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            label: 'Wallet',
            value: 'Receipts',
            onTap: onWallet,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextSteps extends StatelessWidget {
  const _NextSteps({required this.onSend, required this.onActivity});

  final VoidCallback onSend;
  final VoidCallback onActivity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next steps',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _NextStepRow(
            icon: Icons.local_shipping_outlined,
            title: 'Send a parcel',
            subtitle: 'Start a new delivery with current secure payment flow.',
            onTap: onSend,
          ),
          const SizedBox(height: 12),
          _NextStepRow(
            icon: Icons.receipt_long_outlined,
            title: 'Past deliveries',
            subtitle: 'Check Activity for delivery history and receipts.',
            onTap: onActivity,
          ),
        ],
      ),
    );
  }
}

class _NextStepRow extends StatelessWidget {
  const _NextStepRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SenderBottomNav extends StatelessWidget {
  const _SenderBottomNav({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_rounded, 'Home'),
      (Icons.add_box_outlined, 'Send'),
      (Icons.history_rounded, 'Activity'),
      (Icons.account_balance_wallet_outlined, 'Wallet'),
      (Icons.person_outline_rounded, 'Profile'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101820),
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _BottomNavItem(
                  icon: items[i].$1,
                  label: items[i].$2,
                  selected: i == index,
                  onTap: () => onChanged(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : Colors.white54;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 36,
        width: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
