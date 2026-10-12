import 'package:flutter/material.dart';

/// Presentation for the existing Gifts authentication owner. Controllers and
/// sign-in state remain with the Gifts request page; this widget creates no
/// account, gift draft, payment, or separate authentication session.
class GiftsSignIn extends StatefulWidget {
  const GiftsSignIn({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.signingIn,
    required this.onSignIn,
    required this.onBack,
    required this.onPrivacy,
    required this.onTerms,
    this.message,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool signingIn;
  final String? message;
  final Future<void> Function() onSignIn;
  final VoidCallback onBack;
  final VoidCallback onPrivacy;
  final VoidCallback onTerms;

  @override
  State<GiftsSignIn> createState() => _GiftsSignInState();
}

class _GiftsSignInState extends State<GiftsSignIn> {
  final _form = GlobalKey<FormState>();
  bool _showPassword = false;
  bool _submitting = false;
  static const _ink = Color(0xff050809);
  static const _mint = Color(0xffd3eddf);
  static const _muted = Color(0xff95b0a7);

  Future<void> _submit() async {
    if (widget.signingIn || _submitting || !_form.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSignIn();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Text _eyebrow(String value) => Text(value,
      style: const TextStyle(fontSize: 10, letterSpacing: 1.7, color: _muted));

  @override
  Widget build(BuildContext context) {
    final busy = widget.signingIn || _submitting;
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _ink,
        fontFamily: 'D-DIN',
        colorScheme: const ColorScheme.dark(
          primary: _mint,
          onPrimary: Color(0xff102b20),
          surface: _ink,
          onSurface: Color(0xffe5efe8),
          error: Color(0xffffb4ab),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xff0d1513),
          labelStyle: const TextStyle(color: Color(0xffb8ccc0)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xff34483f)),
          ),
        ),
      ),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 760;
            return SingleChildScrollView(
              child: Column(children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: narrow ? 24 : 64, vertical: 22),
                  child: Row(children: [
                    Semantics(
                      label: 'Gifts by Circum',
                      image: true,
                      child: ExcludeSemantics(
                        child: SizedBox(
                          width: 150,
                          height: 62,
                          child: ClipRect(
                            child: OverflowBox(
                              maxWidth: 178,
                              maxHeight: 178,
                              child: Image.asset(
                                  'assets/images/gifts_by_circum_logo.jpg',
                                  width: 178,
                                  height: 178),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                        child: TextButton(
                            onPressed: widget.onBack,
                            child: const Text('← Back to CIRCUM'))),
                  ]),
                ),
                const Divider(height: 1, color: Color(0xff23322d)),
                if (narrow) ...[
                  _storyPanel(narrow: true),
                  _formPanel(busy: busy, narrow: true),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _storyPanel(narrow: false)),
                      Expanded(child: _formPanel(busy: busy, narrow: false)),
                    ],
                  ),
                const Divider(height: 1, color: Color(0xff23322d)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 22,
                      runSpacing: 8,
                      children: [
                        const Text('Thoughtful gifts. Delivered by Circum.',
                            style: TextStyle(fontSize: 12, color: _muted)),
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
    );
  }

  Widget _storyPanel({required bool narrow}) => Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.bottomCenter,
            radius: 1.25,
            colors: [Color(0xff254247), Color(0xff101c22), _ink],
          ),
        ),
        child: CustomPaint(
          painter: const _GiftOrbitPainter(),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: narrow ? 28 : 54, vertical: narrow ? 32 : 78),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _eyebrow('THOUGHTFUL GIFTS. PERSONAL DELIVERY.'),
                  const SizedBox(height: 26),
                  Text('A little closer.',
                      style: TextStyle(
                          fontSize: narrow ? 38 : 57,
                          height: 1.06,
                          letterSpacing: -1.8)),
                  Text('With every\ndelivery.',
                      style: TextStyle(
                          fontFamily: 'GiftsSerif',
                          fontStyle: FontStyle.italic,
                          fontSize: narrow ? 42 : 61,
                          height: 1.06,
                          letterSpacing: -1.8,
                          color: const Color(0xffc9e2db))),
                  const SizedBox(height: 28),
                  const Text(
                      'A thoughtful surprise at their door.\nA Gift Story they can return to.',
                      style:
                          TextStyle(color: _muted, fontSize: 18, height: 1.6)),
                  if (!narrow) ...[
                    const SizedBox(height: 58),
                    const Divider(color: Color(0xff3a514c)),
                    const SizedBox(height: 22),
                    _eyebrow('FROM DELIVERY TO MEMORY'),
                    const SizedBox(height: 12),
                    const Text('The gift arrives.\nThe story stays.',
                        style:
                            TextStyle(fontSize: 24, height: 1.3, color: _mint)),
                  ],
                ]),
          ),
        ),
      );

  Widget _formPanel({required bool busy, required bool narrow}) => Padding(
        padding: EdgeInsets.symmetric(
            horizontal: narrow ? 28 : 54, vertical: narrow ? 38 : 78),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 410),
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _eyebrow('YOUR NEXT THOUGHTFUL DELIVERY'),
                      const SizedBox(height: 20),
                      const Text('Welcome back.',
                          style: TextStyle(
                              fontSize: 46, height: 1.1, letterSpacing: -1.5)),
                      const SizedBox(height: 18),
                      const Text(
                          'Sign in to arrange a gift delivery\nfor someone who matters.',
                          style: TextStyle(
                              fontSize: 18, height: 1.6, color: _muted)),
                      const SizedBox(height: 34),
                      TextFormField(
                        key: const Key('gifts-sign-in-email'),
                        controller: widget.emailController,
                        enabled: !busy,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email
                        ],
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration:
                            const InputDecoration(labelText: 'Email address'),
                        validator: (value) {
                          final email = (value ?? '').trim();
                          if (email.isEmpty) return 'Enter your email address.';
                          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(email))
                            return 'Enter a valid email address.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('gifts-sign-in-password'),
                        controller: widget.passwordController,
                        enabled: !busy,
                        autofillHints: const [AutofillHints.password],
                        obscureText: !_showPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? 'Hide password'
                                : 'Show password',
                            onPressed: busy
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
                        validator: (value) => (value ?? '').isEmpty
                            ? 'Enter your password.'
                            : null,
                      ),
                      if (widget.message != null &&
                          widget.message!.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Semantics(
                            liveRegion: true,
                            child: Text(widget.message!,
                                style: const TextStyle(
                                    color: Color(0xffffc2b8), height: 1.5))),
                      ],
                      const SizedBox(height: 28),
                      FilledButton(
                        key: const Key('gifts-sign-in-submit'),
                        onPressed: busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                  child: Text(
                                      busy
                                          ? 'Signing in…'
                                          : 'Sign in and continue',
                                      style: const TextStyle(fontSize: 16))),
                              if (busy)
                                const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                              else
                                const Icon(Icons.north_east, size: 21),
                            ]),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                          'Next: tell us who it’s for, choose your budget and plan the delivery.',
                          style: TextStyle(
                              color: _muted, fontSize: 12, height: 1.6)),
                      const SizedBox(height: 32),
                      const Divider(color: Color(0xff263c30)),
                      const SizedBox(height: 16),
                      const Text('Use the same account you use for Circum.',
                          style: TextStyle(color: _muted, fontSize: 12)),
                    ]),
              ),
            ),
          ),
        ),
      );
}

class _GiftOrbitPainter extends CustomPainter {
  const _GiftOrbitPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x338eabb5);
    canvas.drawCircle(
        Offset(size.width * .78, size.height * 1.04), size.width * .79, paint);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(size.width * .2, size.height * 1.08),
            width: size.width * 1.3,
            height: size.height * .8),
        paint);
    canvas.drawCircle(Offset(size.width * .18, size.height * .89), 2.4,
        Paint()..color = const Color(0xffc0e7dc));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GiftOrbitPainter oldDelegate) => false;
}
