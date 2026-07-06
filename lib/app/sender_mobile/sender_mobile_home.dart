import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'sender_booking_canvas.dart';

const senderMobileDashboardServiceNames = ['Health+', 'Business', 'Gifts'];
const senderMobileHeroSubtitle =
    'From collection to delivery, every step protected by IRIS.';
const senderMobileDashboardServiceSubtitles = {
  'Health+': 'Trusted medical deliveries',
  'Business': 'Business deliveries',
  'Gifts': 'Thoughtful gfts, delivered.',
};
const senderMobileRecentOrderTitles = ['Passport', 'Prescription collection'];
const senderMobilePreAuthHeadline = 'Deliver anything with confidence.';
const senderMobilePreAuthSubtitle =
    'Fast, trusted delivery powered by IRIS and verified riders.';
const senderMobileAuthSignInHeadline = 'Welcome back';
const senderMobileAuthCreateHeadline = 'Join Circum';
const senderMobileAuthFinePrint =
    "By continuing, you agree to Circum's Terms and Privacy Policy.";

enum _SenderEntryScreen { landing, auth, app }

enum _SenderAuthMode { signIn, createAccount }

class SenderMobileHome extends StatefulWidget {
  const SenderMobileHome({super.key});

  @override
  State<SenderMobileHome> createState() => _SenderMobileHomeState();
}

class _SenderMobileHomeState extends State<SenderMobileHome> {
  var _index = 0;
  var _entry = _SenderEntryScreen.landing;
  var _authMode = _SenderAuthMode.createAccount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SenderTokens.bg,
      body: Stack(
        children: [
          if (_entry == _SenderEntryScreen.app)
            const _SenderMapBackdrop(active: false),
          SafeArea(child: _activeSurface()),
        ],
      ),
      bottomNavigationBar: _entry == _SenderEntryScreen.app
          ? _SenderBottomNav(
              index: _index,
              onChanged: (next) => setState(() => _index = next),
            )
          : null,
    );
  }

  Widget _activeSurface() {
    switch (_entry) {
      case _SenderEntryScreen.landing:
        return _SenderPreAuthLanding(
          onCreateAccount: () => setState(() {
            _authMode = _SenderAuthMode.createAccount;
            _entry = _SenderEntryScreen.auth;
          }),
          onSignIn: () => setState(() {
            _authMode = _SenderAuthMode.signIn;
            _entry = _SenderEntryScreen.auth;
          }),
        );
      case _SenderEntryScreen.auth:
        return _SenderAuthEntry(
          mode: _authMode,
          onBack: () => setState(() => _entry = _SenderEntryScreen.landing),
          onModeChanged: (mode) => setState(() => _authMode = mode),
        );
      case _SenderEntryScreen.app:
        return IndexedStack(
          index: _index,
          children: [
            _SenderDashboard(onStartDelivery: () => setState(() => _index = 1)),
            const SenderBookingCanvas(),
            const _SenderActivitySurface(),
            const _SenderProfileSurface(),
          ],
        );
    }
  }
}

class _SenderPreAuthLanding extends StatelessWidget {
  final VoidCallback onCreateAccount;
  final VoidCallback onSignIn;

  const _SenderPreAuthLanding({
    required this.onCreateAccount,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _AmbientOrbs(count: 2),
        ListView(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
          children: [
            const _CircumWordmarkRow(),
            const SizedBox(height: 46),
            RichText(
              text: TextSpan(
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontSize: 38,
                  height: 1.12,
                  fontWeight: FontWeight.w700,
                ),
                children: const [
                  TextSpan(text: 'Deliver anything with '),
                  TextSpan(
                    text: 'confidence',
                    style: TextStyle(color: _SenderTokens.blue),
                  ),
                  TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            RichText(
              text: TextSpan(
                style: GoogleFonts.inter(
                  color: _SenderTokens.softText,
                  fontSize: 14.5,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                ),
                children: const [
                  TextSpan(text: 'Fast, trusted delivery powered by '),
                  TextSpan(
                    text: 'IRIS',
                    style: TextStyle(
                      color: _SenderTokens.blue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(text: ' and verified riders.'),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _SenderPrimaryAction(
              label: 'Create account',
              semanticLabel: 'Create account',
              onTap: onCreateAccount,
            ),
            Semantics(
              button: true,
              label: 'Sign in',
              child: TextButton(
                onPressed: onSignIn,
                child: Text(
                  'Sign in',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const _TrustHighlightGrid(),
            const SizedBox(height: 34),
            const _WhyCircumSection(),
            const SizedBox(height: 34),
            const _ServicesPreviewSection(),
            const SizedBox(height: 20),
            const _PreAuthSocialProof(),
            const SizedBox(height: 24),
            const _PreAuthFooterLinks(),
          ],
        ),
      ],
    );
  }
}

class _SenderAuthEntry extends StatefulWidget {
  final _SenderAuthMode mode;
  final VoidCallback onBack;
  final ValueChanged<_SenderAuthMode> onModeChanged;

  const _SenderAuthEntry({
    required this.mode,
    required this.onBack,
    required this.onModeChanged,
  });

  @override
  State<_SenderAuthEntry> createState() => _SenderAuthEntryState();
}

class _SenderAuthEntryState extends State<_SenderAuthEntry> {
  final _identity = TextEditingController();
  final _password = TextEditingController();
  var _showErrors = false;

  bool get _isSignIn => widget.mode == _SenderAuthMode.signIn;

  @override
  void dispose() {
    _identity.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const _AmbientOrbs(count: 1),
        ListView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          children: [
            Row(
              children: [
                _GlassIconChip(
                  icon: Icons.chevron_left_rounded,
                  label: 'Back',
                  onTap: widget.onBack,
                ),
                const Spacer(),
                const _CircumMarkChip(),
              ],
            ),
            const SizedBox(height: 36),
            _AuthSegmentedControl(
              mode: widget.mode,
              onChanged: (mode) {
                setState(() => _showErrors = false);
                widget.onModeChanged(mode);
              },
            ),
            const SizedBox(height: 26),
            Text(
              _isSignIn
                  ? senderMobileAuthSignInHeadline
                  : senderMobileAuthCreateHeadline,
              style: GoogleFonts.dmSerifDisplay(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isSignIn
                  ? 'Sign in to track deliveries and manage your account.'
                  : 'Create an account to start sending with confidence.',
              style: GoogleFonts.inter(
                color: _SenderTokens.muted,
                fontSize: 13.5,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 26),
            _AuthField(
              controller: _identity,
              label: 'EMAIL OR PHONE',
              hint: 'you@email.com',
              keyboardType: TextInputType.emailAddress,
              errorText: _showErrors && _identity.text.trim().isEmpty
                  ? 'Email or phone is required'
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            if (_isSignIn) ...[
              const SizedBox(height: 14),
              _AuthField(
                controller: _password,
                label: 'PASSWORD',
                hint: 'Password',
                obscureText: true,
                errorText: _showErrors && _password.text.isEmpty
                    ? 'Password is required'
                    : null,
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 14),
            _SenderPrimaryAction(
              label: _isSignIn ? 'Sign in' : 'Create account',
              semanticLabel: _isSignIn ? 'Sign in' : 'Create account',
              onTap: _submit,
            ),
            const SizedBox(height: 26),
            const _LabelledDivider(),
            const SizedBox(height: 22),
            const _SocialAuthButton(
              icon: Icons.apple_rounded,
              label: 'Continue with Apple',
            ),
            const SizedBox(height: 10),
            const _SocialAuthButton(
              icon: Icons.g_mobiledata,
              label: 'Continue with Google',
            ),
            const SizedBox(height: 28),
            _AuthSwitchLine(
              isSignIn: _isSignIn,
              onTap: () {
                setState(() => _showErrors = false);
                widget.onModeChanged(
                  _isSignIn
                      ? _SenderAuthMode.createAccount
                      : _SenderAuthMode.signIn,
                );
              },
            ),
            const SizedBox(height: 22),
            const _AuthFinePrint(),
          ],
        ),
      ],
    );
  }

  void _submit() {
    final validIdentity = _identity.text.trim().isNotEmpty;
    final validPassword = !_isSignIn || _password.text.isNotEmpty;
    setState(() => _showErrors = true);
    if (!validIdentity || !validPassword) return;
    // TODO(sender-mobile-auth): Wire to the existing auth/onboarding handler.
  }
}

class _AmbientOrbs extends StatefulWidget {
  final int count;

  const _AmbientOrbs({required this.count});

  @override
  State<_AmbientOrbs> createState() => _AmbientOrbsState();
}

class _AmbientOrbsState extends State<_AmbientOrbs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_controller.value);
            return Stack(
              children: [
                Positioned(
                  top: -120 + (t * 22),
                  left: -84 + (t * 18),
                  child: const _Orb(size: 270, opacity: .38),
                ),
                if (widget.count > 1)
                  Positioned(
                    top: 118 - (t * 24),
                    right: -92 + (t * 16),
                    child: const _Orb(size: 228, opacity: .28),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final double size;
  final double opacity;

  const _Orb({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 54, sigmaY: 54),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              _SenderTokens.blue.withValues(alpha: opacity),
              _SenderTokens.blue.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircumWordmarkRow extends StatelessWidget {
  const _CircumWordmarkRow();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Circum',
      image: true,
      child: Row(
        children: [
          const _CircumMarkChip(filled: true),
          const SizedBox(width: 10),
          Image.asset(
            'assets/images/circum_wordmark.png',
            height: 26,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ],
      ),
    );
  }
}

class _CircumMarkChip extends StatelessWidget {
  final bool filled;

  const _CircumMarkChip({this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: filled ? 30 : 34,
      height: filled ? 30 : 34,
      decoration: BoxDecoration(
        color: filled ? _SenderTokens.blue : _SenderTokens.glass,
        borderRadius: BorderRadius.circular(filled ? 9 : 12),
        border: Border.all(color: _SenderTokens.glassBorder),
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        color: Colors.white,
        size: filled ? 15 : 17,
      ),
    );
  }
}

class _GlassIconChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GlassIconChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _SenderTokens.glass,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _SenderTokens.glassBorder),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _SenderPrimaryAction extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  const _SenderPrimaryAction({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: _SenderTokens.blue,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrustHighlightGrid extends StatelessWidget {
  const _TrustHighlightGrid();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.auto_awesome_rounded, 'IRIS'),
      (Icons.shield_outlined, 'Vanguard'),
      (Icons.visibility_outlined, 'Live Tracking'),
      (Icons.person_outline_rounded, 'Trusted Riders'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.18,
      mainAxisExtent: 88,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: [
        for (final item in items)
          _PreAuthGlassCard(icon: item.$1, label: item.$2),
      ],
    );
  }
}

class _PreAuthGlassCard extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PreAuthGlassCard({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: _SenderTokens.glass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _SenderTokens.glassBorder),
          ),
          child: Row(
            children: [
              _MiniIcon(icon: icon, color: _SenderTokens.lightBlue),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
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

class _WhyCircumSection extends StatelessWidget {
  const _WhyCircumSection();

  @override
  Widget build(BuildContext context) {
    return const _PreAuthSection(
      eyebrow: 'BUILT IN',
      children: [
        _BenefitRow(
          icon: Icons.credit_card_rounded,
          title: 'Transparent pricing',
          body: 'Clear costs before you continue.',
        ),
        _BenefitRow(
          icon: Icons.visibility_outlined,
          title: 'Real-time tracking',
          body: 'Follow every step of the journey.',
        ),
        _BenefitRow(
          icon: Icons.shield_outlined,
          title: 'Built for trust',
          body: 'Verified riders and safer handovers.',
        ),
      ],
    );
  }
}

class _ServicesPreviewSection extends StatelessWidget {
  const _ServicesPreviewSection();

  @override
  Widget build(BuildContext context) {
    return const _PreAuthSection(
      eyebrow: 'COMING WITH YOUR ACCOUNT',
      children: [
        _ServicePreviewCard(
          icon: Icons.card_giftcard_rounded,
          title: 'Gifts',
          body: 'Curated gifts delivered with care.',
          accent: _SenderTokens.gifts,
        ),
        _ServicePreviewCard(
          icon: Icons.health_and_safety_rounded,
          title: 'Health+',
          body: 'Trusted prescription and care deliveries.',
          accent: _SenderTokens.health,
        ),
        _ServicePreviewCard(
          icon: Icons.business_center_rounded,
          title: 'Business',
          body: 'Delivery tools for growing teams.',
          accent: _SenderTokens.blue,
        ),
      ],
    );
  }
}

class _PreAuthSection extends StatelessWidget {
  final String eyebrow;
  final List<Widget> children;

  const _PreAuthSection({required this.eyebrow, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: GoogleFonts.jetBrainsMono(
            color: _SenderTokens.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _SenderTokens.hairline)),
      ),
      child: Row(
        children: [
          _MiniIcon(icon: icon, color: _SenderTokens.lightBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: _SenderTokens.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicePreviewCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color accent;

  const _ServicePreviewCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _SenderTokens.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _SenderTokens.hairline),
      ),
      child: Row(
        children: [
          _MiniIcon(icon: icon, color: accent),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: _SenderTokens.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          _AfterJoinPill(accent: accent),
        ],
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _MiniIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .38)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .16), blurRadius: 14),
        ],
      ),
      child: Icon(icon, color: color, size: 18.5),
    );
  }
}

class _AfterJoinPill extends StatelessWidget {
  final Color accent;

  const _AfterJoinPill({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: .24)),
      ),
      child: Text(
        'After you join',
        style: GoogleFonts.jetBrainsMono(
          color: Colors.white.withValues(alpha: .72),
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PreAuthSocialProof extends StatelessWidget {
  const _PreAuthSocialProof();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Trusted by people sending everything from forgotten passports to meaningful gifts.',
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        color: _SenderTokens.muted,
        fontSize: 12.5,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _PreAuthFooterLinks extends StatelessWidget {
  const _PreAuthFooterLinks();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Terms, Privacy, Help',
      child: Text(
        'Terms · Privacy · Help',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          color: _SenderTokens.muted,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _AuthSegmentedControl extends StatelessWidget {
  final _SenderAuthMode mode;
  final ValueChanged<_SenderAuthMode> onChanged;

  const _AuthSegmentedControl({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _SenderTokens.glass,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _SenderTokens.glassBorder),
      ),
      child: Row(
        children: [
          _AuthTab(
            label: 'Sign in',
            active: mode == _SenderAuthMode.signIn,
            onTap: () => onChanged(_SenderAuthMode.signIn),
          ),
          _AuthTab(
            label: 'Create account',
            active: mode == _SenderAuthMode.createAccount,
            onTap: () => onChanged(_SenderAuthMode.createAccount),
          ),
        ],
      ),
    );
  }
}

class _AuthTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _AuthTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? _SenderTokens.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: active ? Colors.white : _SenderTokens.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? errorText;
  final ValueChanged<String> onChanged;

  const _AuthField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.errorText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              color: _SenderTokens.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            onChanged: onChanged,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: .34),
              ),
              errorText: errorText,
              errorStyle: GoogleFonts.inter(
                color: const Color(0xFFFCA5A5),
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: _SenderTokens.glass,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _SenderTokens.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _SenderTokens.blue),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFFCA5A5)),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFFCA5A5)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabelledDivider extends StatelessWidget {
  const _LabelledDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: _SenderTokens.hairline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR CONTINUE WITH',
            style: GoogleFonts.jetBrainsMono(
              color: _SenderTokens.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Expanded(child: Divider(color: _SenderTokens.hairline)),
      ],
    );
  }
}

class _SocialAuthButton extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SocialAuthButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: OutlinedButton.icon(
        onPressed: () {
          // TODO(sender-mobile-auth): Wire social provider handlers when enabled.
        },
        icon: Icon(icon, color: Colors.white, size: 21),
        label: Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: _SenderTokens.glassBorder),
          backgroundColor: _SenderTokens.glass,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _AuthSwitchLine extends StatelessWidget {
  final bool isSignIn;
  final VoidCallback onTap;

  const _AuthSwitchLine({required this.isSignIn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isSignIn ? 'Create account' : 'Sign in',
      child: GestureDetector(
        onTap: onTap,
        child: Text.rich(
          TextSpan(
            text: isSignIn ? 'New to Circum? ' : 'Already have an account? ',
            style: GoogleFonts.inter(
              color: _SenderTokens.muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            children: [
              TextSpan(
                text: isSignIn ? 'Create account' : 'Sign in',
                style: GoogleFonts.inter(
                  color: _SenderTokens.blue,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _AuthFinePrint extends StatelessWidget {
  const _AuthFinePrint();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: 'By continuing, you agree to Circum\'s ',
        style: GoogleFonts.inter(
          color: _SenderTokens.muted,
          fontSize: 11,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text: 'Terms',
            style: GoogleFonts.inter(
              color: _SenderTokens.blue,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: GoogleFonts.inter(
              color: _SenderTokens.blue,
              fontWeight: FontWeight.w700,
            ),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _SenderDashboard extends StatelessWidget {
  final VoidCallback onStartDelivery;

  const _SenderDashboard({required this.onStartDelivery});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Row(
          children: [
            const Text(
              'CIRCUM',
              style: TextStyle(
                color: _SenderTokens.lightBlue,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.4,
              ),
            ),
            const Spacer(),
            _IconGlassButton(icon: Icons.notifications_none_rounded),
            const SizedBox(width: 10),
            const _SenderAvatar(initials: 'JA'),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Good morning, Jason',
          style: TextStyle(
            color: Colors.white,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 18),
        _HeroSendCard(onTap: onStartDelivery),
        const SizedBox(height: 18),
        const _YourCircumHub(),
        const SizedBox(height: 16),
        const _RecentOrdersCard(),
      ],
    );
  }
}

class _HeroSendCard extends StatelessWidget {
  final VoidCallback onTap;

  const _HeroSendCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: EdgeInsets.zero,
      radius: 32,
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: Container(
          height: 236,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _SenderTokens.midnight.withValues(alpha: .94),
                _SenderTokens.blue.withValues(alpha: .42),
                _SenderTokens.bg,
              ],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: _HeroRouteArt()),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .25),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _SenderTokens.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        color: _SenderTokens.lightBlue,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '2 orders',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(left: 0, top: 0, child: _IrisOrb(size: 58)),
              Positioned(
                left: 0,
                right: 118,
                bottom: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Send a parcel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 9),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          color: Color(0xFFD8E7FF),
                          height: 1.35,
                          fontSize: 14,
                        ),
                        children: [
                          TextSpan(
                            text:
                                'From collection to delivery, every step protected by ',
                          ),
                          TextSpan(
                            text: 'IRIS',
                            style: TextStyle(
                              color: _SenderTokens.blue,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          TextSpan(text: '.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: _SenderTokens.blue.withValues(alpha: .28),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Send now',
                            style: TextStyle(
                              color: _SenderTokens.bg,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: _SenderTokens.blue,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YourCircumHub extends StatelessWidget {
  const _YourCircumHub();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Circum',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ServiceCard(
                title: 'Health+',
                subtitle: 'Trusted medical deliveries',
                icon: Icons.health_and_safety_rounded,
                accent: _SenderTokens.health,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _ServiceCard(
                title: 'Business',
                subtitle: 'Business deliveries',
                icon: Icons.business_center_rounded,
                accent: _SenderTokens.business,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _ServiceCard(
                title: 'Gifts',
                subtitle: 'Thoughtful gfts, delivered.',
                icon: Icons.card_giftcard_rounded,
                accent: _SenderTokens.gifts,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ServiceCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _ServiceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _pressed ? 1.02 : 1,
        child: _GlassCard(
          radius: 24,
          padding: const EdgeInsets.all(12),
          child: AspectRatio(
            aspectRatio: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                widget.title == 'Gifts'
                    ? const _PremiumGiftIcon()
                    : _ServiceIcon(icon: widget.icon, accent: widget.accent),
                const Spacer(),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .1,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _SenderTokens.muted,
                    height: 1.22,
                    fontSize: 11.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: widget.accent,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceIcon extends StatelessWidget {
  final IconData icon;
  final Color accent;

  const _ServiceIcon({required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .38)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .18), blurRadius: 18),
        ],
      ),
      child: Icon(icon, color: accent, size: 24),
    );
  }
}

class _PremiumGiftIcon extends StatelessWidget {
  const _PremiumGiftIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _SenderTokens.giftGold.withValues(alpha: .22),
            _SenderTokens.gifts.withValues(alpha: .18),
            _SenderTokens.iceBlue.withValues(alpha: .14),
          ],
        ),
        border: Border.all(color: _SenderTokens.pearl.withValues(alpha: .36)),
        boxShadow: [
          BoxShadow(
            color: _SenderTokens.gifts.withValues(alpha: .20),
            blurRadius: 20,
          ),
        ],
      ),
      child: CustomPaint(painter: const _PremiumGiftPainter()),
    );
  }
}

class _PremiumGiftPainter extends CustomPainter {
  const _PremiumGiftPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * .22,
        size.height * .38,
        size.width * .56,
        size.height * .38,
      ),
      const Radius.circular(5),
    );
    final lid = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * .18,
        size.height * .30,
        size.width * .64,
        size.height * .16,
      ),
      const Radius.circular(5),
    );
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _SenderTokens.giftGold,
          _SenderTokens.pearl,
          _SenderTokens.gifts,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(box, bodyPaint);
    canvas.drawRRect(lid, bodyPaint);

    final ribbonPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          _SenderTokens.gifts,
          _SenderTokens.iceBlue,
          _SenderTokens.softLilac,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .46,
          size.height * .29,
          size.width * .10,
          size.height * .47,
        ),
        const Radius.circular(3),
      ),
      ribbonPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .18,
          size.height * .43,
          size.width * .64,
          size.height * .08,
        ),
        const Radius.circular(3),
      ),
      ribbonPaint,
    );

    final bowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = _SenderTokens.pearl;
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * .30,
        size.height * .18,
        size.width * .22,
        size.height * .18,
      ),
      math.pi * .1,
      math.pi * 1.25,
      false,
      bowPaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * .48,
        size.height * .18,
        size.width * .22,
        size.height * .18,
      ),
      math.pi * -.35,
      math.pi * 1.25,
      false,
      bowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PremiumGiftPainter oldDelegate) => false;
}

class _HeroRouteArt extends StatelessWidget {
  const _HeroRouteArt();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HeroRoutePainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _HeroRoutePainter extends CustomPainter {
  const _HeroRoutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .035)
      ..strokeWidth = 1;
    for (var x = size.width * .42; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x - 16, size.height), grid);
    }
    for (var y = 8.0; y < size.height; y += 28) {
      canvas.drawLine(
        Offset(size.width * .38, y),
        Offset(size.width, y + 6),
        grid,
      );
    }
    final start = Offset(size.width * .58, size.height * .70);
    final end = Offset(size.width * .90, size.height * .38);
    final route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        size.width * .66,
        size.height * .36,
        size.width * .82,
        size.height * .86,
        end.dx,
        end.dy,
      );
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            _SenderTokens.lightBlue.withValues(alpha: .18),
            _SenderTokens.iris.withValues(alpha: .74),
            _SenderTokens.health.withValues(alpha: .35),
          ],
        ).createShader(rect),
    );
    _dot(canvas, start, _SenderTokens.blue);
    _dot(canvas, end, _SenderTokens.health);
  }

  void _dot(Canvas canvas, Offset point, Color color) {
    canvas.drawCircle(point, 16, Paint()..color = color.withValues(alpha: .11));
    canvas.drawCircle(point, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HeroRoutePainter oldDelegate) => false;
}

class _RecentOrdersCard extends StatelessWidget {
  const _RecentOrdersCard();

  @override
  Widget build(BuildContext context) {
    return const _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent orders',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Recent deliveries',
                      style: TextStyle(color: _SenderTokens.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: _SenderTokens.muted),
            ],
          ),
          SizedBox(height: 14),
          _OrderLine(
            title: 'Passport',
            subtitle: 'Marylebone → Chelsea',
            status: 'In transit',
            icon: Icons.badge_rounded,
            accent: _SenderTokens.business,
          ),
          _OrderLine(
            title: 'Prescription collection',
            subtitle: 'Health+ verified',
            status: 'Delivered',
            icon: Icons.medical_services_rounded,
            accent: _SenderTokens.health,
          ),
        ],
      ),
    );
  }
}

class _OrderLine extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final IconData icon;
  final Color accent;

  const _OrderLine({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _SenderTokens.border),
      ),
      child: Row(
        children: [
          _ServiceIcon(icon: icon, accent: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: _SenderTokens.muted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _SenderTokens.health.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _SenderTokens.health.withValues(alpha: .32),
              ),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: _SenderTokens.health,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SenderActivitySurface extends StatelessWidget {
  const _SenderActivitySurface();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: _GlassCard(
        child: Text(
          'Activity and live tracking appear here after booking.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _SenderProfileSurface extends StatelessWidget {
  const _SenderProfileSurface();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: _GlassCard(
        child: Text(
          'Profile, saved places and support stay connected to the existing app.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _SenderBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _SenderBottomNav({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xEE0B1020),
        border: Border(top: BorderSide(color: _SenderTokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _NavItem(
              index: 0,
              selected: index,
              icon: Icons.home_rounded,
              label: 'Home',
              onTap: onChanged,
            ),
            _NavItem(
              index: 1,
              selected: index,
              icon: Icons.near_me_rounded,
              label: 'Send',
              onTap: onChanged,
            ),
            _NavItem(
              index: 2,
              selected: index,
              icon: Icons.route_rounded,
              label: 'Activity',
              onTap: onChanged,
            ),
            _NavItem(
              index: 3,
              selected: index,
              icon: Icons.person_rounded,
              label: 'Profile',
              onTap: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final int selected;
  final IconData icon;
  final String label;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.index,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = index == selected;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: active ? _SenderTokens.lightBlue : _SenderTokens.muted,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: active ? _SenderTokens.lightBlue : _SenderTokens.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SenderAvatar extends StatelessWidget {
  final String initials;

  const _SenderAvatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: _SenderTokens.blue,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _IconGlassButton extends StatelessWidget {
  final IconData icon;

  const _IconGlassButton({required this.icon});

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(10),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _SenderTokens.glass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: _SenderTokens.border),
            boxShadow: [
              BoxShadow(
                color: _SenderTokens.blue.withValues(alpha: .10),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _IrisOrb extends StatefulWidget {
  final double size;

  const _IrisOrb({this.size = 48});

  @override
  State<_IrisOrb> createState() => _IrisOrbState();
}

class _IrisOrbState extends State<_IrisOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [
                _SenderTokens.iris,
                _SenderTokens.vanguard,
                _SenderTokens.bg,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: _SenderTokens.iris.withValues(
                  alpha: .22 + _controller.value * .12,
                ),
                blurRadius: 24,
              ),
            ],
          ),
          child: Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: widget.size * .42,
          ),
        );
      },
    );
  }
}

class _SenderMapBackdrop extends StatefulWidget {
  final bool active;

  const _SenderMapBackdrop({required this.active});

  @override
  State<_SenderMapBackdrop> createState() => _SenderMapBackdropState();
}

class _SenderMapBackdropState extends State<_SenderMapBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _SenderMapPainter(t: _controller.value, active: widget.active),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SenderMapPainter extends CustomPainter {
  final double t;
  final bool active;

  const _SenderMapPainter({required this.t, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_SenderTokens.bg, _SenderTokens.midnight],
        ).createShader(rect),
    );

    final drift = math.sin(t * math.pi * 2) * 10;
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = 1;
    for (var x = -80.0 + drift; x < size.width + 80; x += 52) {
      canvas.drawLine(Offset(x, 0), Offset(x + 26, size.height), grid);
    }
    for (var y = -80.0 - drift; y < size.height + 80; y += 58) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 18), grid);
    }

    final pickup = Offset(size.width * .26, size.height * .34);
    final dropoff = Offset(size.width * .78, size.height * .22);
    final route = Path()
      ..moveTo(pickup.dx, pickup.dy)
      ..cubicTo(
        size.width * .28,
        size.height * .14,
        size.width * .62,
        size.height * .44,
        dropoff.dx,
        dropoff.dy,
      );
    canvas.drawPath(
      route,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = _SenderTokens.lightBlue.withValues(alpha: active ? .7 : .22),
    );
    _pin(canvas, pickup, _SenderTokens.blue, t);
    _pin(canvas, dropoff, const Color(0xFF22C55E), (t + .45) % 1);
  }

  void _pin(Canvas canvas, Offset point, Color color, double phase) {
    canvas.drawCircle(
      point,
      8 + phase * 20,
      Paint()..color = color.withValues(alpha: .15 * (1 - phase)),
    );
    canvas.drawCircle(point, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SenderMapPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.active != active;
}

class _SenderTokens {
  static const bg = Color(0xFF07090F);
  static const midnight = Color(0xFF0B1020);
  static const blue = Color(0xFF3B82F6);
  static const lightBlue = Color(0xFF60A5FA);
  static const vanguard = Color(0xFF2563EB);
  static const iris = Color(0xFF38BDF8);
  static const health = Color(0xFF22C55E);
  static const business = Color(0xFF94A3B8);
  static const gifts = Color(0xFFE8B4A0);
  static const giftGold = Color(0xFFE7C98F);
  static const pearl = Color(0xFFF7F1E4);
  static const iceBlue = Color(0xFFA5D8FF);
  static const softLilac = Color(0xFFCDB4F6);
  static const muted = Color(0xFF9CA3AF);
  static const softText = Color(0xB8F5F7FB);
  static const panel = Color(0xFF0D111C);
  static const hairline = Color(0x14F5F7FB);
  static const border = Color(0x29FFFFFF);
  static const glass = Color(0x0DF5F7FB);
  static const glassBorder = Color(0x1AF5F7FB);
}
