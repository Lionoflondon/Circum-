import 'circum_home_link.dart';
import 'package:flutter/material.dart';

/// Account presentation only. The sender portal owns authentication and state.
class AccountAccessPage extends StatefulWidget {
  const AccountAccessPage({
    super.key,
    required this.signupMode,
    required this.busy,
    required this.email,
    required this.password,
    required this.fullName,
    required this.phone,
    required this.referralCode,
    required this.onToggleMode,
    required this.onLogIn,
    required this.onSignUp,
    required this.onForgotPassword,
    required this.onBack,
    required this.onPrivacy,
    required this.onTerms,
    this.message,
  });

  final bool signupMode;
  final bool busy;
  final String? message;
  final TextEditingController email, password, fullName, phone, referralCode;
  final VoidCallback onToggleMode, onLogIn, onSignUp, onForgotPassword;
  final VoidCallback onBack, onPrivacy, onTerms;

  @override
  State<AccountAccessPage> createState() => _AccountAccessPageState();
}

class _AccountAccessPageState extends State<AccountAccessPage> {
  final _form = GlobalKey<FormState>();
  final _emailField = GlobalKey<FormFieldState<String>>();
  bool _showPassword = false;
  static const _ink = Color(0xff152820);
  static const _muted = Color(0xff59695f);
  static const _blue = Color(0xff304feb);

  void _submit() {
    if (widget.busy || !_form.currentState!.validate()) return;
    if (widget.signupMode) {
      widget.onSignUp();
    } else {
      widget.onLogIn();
    }
  }

  void _toggle() {
    if (widget.busy) return;
    // Recreate form validation without resetting the parent's controllers.
    setState(() => _showPassword = false);
    widget.onToggleMode();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(fontFamily: 'D-DIN', fontSize: 14, color: _ink),
      child: Theme(
        data: ThemeData(
          brightness: Brightness.light,
          fontFamily: 'D-DIN',
          scaffoldBackgroundColor: const Color(0xfffafbf8),
          colorScheme: ColorScheme.fromSeed(
            seedColor: _blue,
            primary: _blue,
            onSurface: _ink,
            surface: Colors.white,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xfff6f8f5),
            labelStyle: const TextStyle(color: _muted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 17, vertical: 19),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xffdce3dd)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _blue, width: 1.5),
            ),
          ),
        ),
        child: ColoredBox(
          color: const Color(0xfffafbf8),
          child: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 850;
              return SingleChildScrollView(
                child: Column(children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: wide ? 48 : 24, vertical: 22),
                    child: Row(children: [
                      CircumHomeLink(child: Image.asset('assets/images/circum_wordmark.png',
                          width: 125, height: 32, semanticLabel: 'CIRCUM')),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: const Text('Home'),
                      ),
                    ]),
                  ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1300),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                            wide ? 32 : 24, wide ? 12 : 4, wide ? 32 : 24, 24),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Expanded(child: _welcome()),
                                    Expanded(
                                        child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          48, 30, 32, 24),
                                      child: _accountForm(),
                                    )),
                                  ])
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    const Text('DELIVERY STARTS WITH YOU',
                                        style: TextStyle(
                                            color: _blue,
                                            fontSize: 11,
                                            letterSpacing: 1.6)),
                                    const SizedBox(height: 22),
                                    _accountForm(),
                                  ]),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
                    child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 20,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Thoughtfully delivered. CIRCUM.',
                              style: TextStyle(color: _muted, fontSize: 12)),
                          TextButton(
                              onPressed: widget.onPrivacy,
                              child: const Text('Privacy')),
                          TextButton(
                              onPressed: widget.onTerms,
                              child: const Text('Terms')),
                        ]),
                  ),
                ]),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _welcome() => Container(
        constraints: const BoxConstraints(minHeight: 650),
        padding: const EdgeInsets.all(42),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffe1f1e9), Color(0xffe5eafb), Color(0xfff2eaf4)],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('A WORLD WITHIN REACH',
              style: TextStyle(fontSize: 11, letterSpacing: 2, color: _muted)),
          const SizedBox(height: 34),
          const Text('Every delivery.\nA little closer.',
              style: TextStyle(
                  fontFamily: 'D-DIN-Bold',
                  fontSize: 62,
                  letterSpacing: -2,
                  height: 1.02,
                  color: _ink)),
          const SizedBox(height: 22),
          const Text(
              'The things you need. The people you love.\nOne account to bring them closer.',
              style: TextStyle(fontSize: 18, height: 1.5, color: _muted)),
          const SizedBox(height: 28),
          const SizedBox(
              height: 200,
              width: double.infinity,
              child: ExcludeSemantics(
                  child: CustomPaint(painter: _DeliveryPathPainter()))),
          const SizedBox(height: 28),
          const Divider(color: Color(0xffc7d1d5)),
          const SizedBox(height: 18),
          const Wrap(spacing: 20, runSpacing: 12, children: [
            _DeliveryLabel(
                icon: Icons.inventory_2_outlined, text: 'Send parcels'),
            _DeliveryLabel(icon: Icons.card_giftcard, text: 'Deliver gifts'),
            _DeliveryLabel(
                icon: Icons.route_outlined, text: 'Follow the journey'),
          ]),
        ]),
      );

  Widget _accountForm() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AutofillGroup(
            child: Form(
              key: _form,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: _modeButton('Log in', !widget.signupMode)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _modeButton('Sign up', widget.signupMode)),
                    ]),
                    const SizedBox(height: 34),
                    Text(
                        widget.signupMode
                            ? 'Your next delivery\nstarts here.'
                            : 'Good to see you.',
                        style: const TextStyle(
                            fontFamily: 'D-DIN-Bold',
                            fontSize: 38,
                            height: 1.08,
                            letterSpacing: -0.8,
                            color: _ink)),
                    const SizedBox(height: 12),
                    Text(
                        widget.signupMode
                            ? 'Create your CIRCUM account and make your first move.'
                            : 'Log in for your deliveries, gifts and everything along the way.',
                        style: const TextStyle(
                            color: _muted, height: 1.5, fontSize: 16)),
                    const SizedBox(height: 28),
                    if (widget.signupMode) ...[
                      _field('Full name', widget.fullName,
                          autofill: AutofillHints.name,
                          validator: (s) => s == null || s.trim().isEmpty
                              ? 'Enter your full name.'
                              : null),
                      const SizedBox(height: 16),
                      _field('Phone number', widget.phone,
                          autofill: AutofillHints.telephoneNumber,
                          keyboard: TextInputType.phone),
                      const SizedBox(height: 16),
                    ],
                    _field('Email address', widget.email,
                        fieldKey: _emailField,
                        autofill: AutofillHints.email,
                        keyboard: TextInputType.emailAddress,
                        validator: (s) => s == null ||
                                !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                    .hasMatch(s.trim())
                            ? 'Enter a valid email address.'
                            : null),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: ValueKey('password-${widget.signupMode}'),
                      controller: widget.password,
                      enabled: !widget.busy,
                      obscureText: !_showPassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: [
                        widget.signupMode
                            ? AutofillHints.newPassword
                            : AutofillHints.password
                      ],
                      textInputAction: widget.signupMode
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!widget.signupMode) _submit();
                      },
                      validator: (s) => s == null || s.isEmpty
                          ? 'Enter your password.'
                          : widget.signupMode && s.length < 6
                              ? 'Use at least 6 characters.'
                              : null,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: widget.signupMode
                            ? 'Use at least 6 characters.'
                            : null,
                        suffixIcon: IconButton(
                          tooltip:
                              _showPassword ? 'Hide password' : 'Show password',
                          onPressed: widget.busy
                              ? null
                              : () => setState(
                                  () => _showPassword = !_showPassword),
                          icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20),
                        ),
                      ),
                    ),
                    if (widget.signupMode) ...[
                      const SizedBox(height: 16),
                      _field('Referral code (optional)', widget.referralCode,
                          keyboard: TextInputType.text, last: true),
                      const SizedBox(height: 8),
                      const Text(
                          'Have a friend’s code? Rewards unlock after your first completed paid delivery.',
                          style: TextStyle(
                              color: _muted, fontSize: 12, height: 1.5)),
                    ] else
                      Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: widget.busy
                                  ? null
                                  : () {
                                      if (_emailField.currentState!
                                          .validate()) {
                                        widget.onForgotPassword();
                                      }
                                    },
                              child: const Text('Forgot password?'))),
                    if (widget.message?.isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      Semantics(
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: const Color(0xffeef1ff),
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(widget.message!,
                                style:
                                    const TextStyle(color: _ink, height: 1.45)),
                          )),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: widget.busy ? null : _submit,
                          style: FilledButton.styleFrom(
                              backgroundColor: _blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
                          child: widget.busy
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                      SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white)),
                                      SizedBox(width: 12),
                                      Flexible(child: Text('Please wait')),
                                    ])
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                      Flexible(
                                          child: Text(
                                              widget.signupMode
                                                  ? 'Create account'
                                                  : 'Log in',
                                              style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight:
                                                      FontWeight.w700))),
                                      const SizedBox(width: 12),
                                      const Icon(Icons.arrow_forward, size: 19),
                                    ]),
                        )),
                    const SizedBox(height: 18),
                    const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline, size: 14, color: _muted),
                          SizedBox(width: 6),
                          Flexible(
                              child: Text(
                                  'Your account. Your deliveries. All together.',
                                  style:
                                      TextStyle(fontSize: 12, color: _muted))),
                        ]),
                  ]),
            ),
          ),
        ),
      );

  Widget _modeButton(String text, bool selected) => Semantics(
        selected: selected,
        child: TextButton(
          onPressed: selected || widget.busy ? null : _toggle,
          style: TextButton.styleFrom(
            backgroundColor: selected ? _ink : const Color(0xffedf0ea),
            disabledForegroundColor: selected ? Colors.white : _muted,
            foregroundColor: _muted,
            minimumSize: const Size(48, 48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
          child: Text(text,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _field(String label, TextEditingController controller,
          {GlobalKey<FormFieldState<String>>? fieldKey,
          String? autofill,
          TextInputType? keyboard,
          String? Function(String?)? validator,
          bool last = false}) =>
      TextFormField(
        key: fieldKey ?? ValueKey(label),
        controller: controller,
        enabled: !widget.busy,
        keyboardType: keyboard,
        autofillHints: autofill == null ? null : [autofill],
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        onFieldSubmitted: (_) {
          if (last) _submit();
        },
        validator: validator,
        decoration: InputDecoration(labelText: label),
      );
}

class _DeliveryLabel extends StatelessWidget {
  const _DeliveryLabel({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: const Color(0xff59695f)),
        const SizedBox(width: 7),
        Text(text,
            style: const TextStyle(fontSize: 12, color: Color(0xff152820))),
      ]);
}

class _DeliveryPathPainter extends CustomPainter {
  const _DeliveryPathPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width * .12, size.height * .74);
    final end = Offset(size.width * .86, size.height * .28);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(size.width * .55, size.height * 1.05, size.width * .34,
          -size.height * .05, end.dx, end.dy);
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xff6e85d8)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
    for (final point in [start, end]) {
      canvas.drawCircle(point, 24, Paint()..color = const Color(0x22304feb));
      canvas.drawCircle(point, 8, Paint()..color = const Color(0xff304feb));
      canvas.drawCircle(point, 3, Paint()..color = Colors.white);
    }
    final center = Offset(size.width * .5, size.height * .49);
    final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 70, height: 70),
        const Radius.circular(17));
    canvas.drawRRect(rect, Paint()..color = const Color(0xfffafbf8));
    final box = Rect.fromCenter(center: center, width: 28, height: 28);
    final pen = Paint()
      ..color = const Color(0xff304feb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(3)), pen);
    canvas.drawLine(
        Offset(center.dx, box.top), Offset(center.dx, box.bottom), pen);
    canvas.drawLine(
        Offset(box.left, center.dy - 4), Offset(box.right, center.dy - 4), pen);
  }

  @override
  bool shouldRepaint(_DeliveryPathPainter oldDelegate) => false;
}
