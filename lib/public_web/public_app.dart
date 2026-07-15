// Mechanical extraction of the Circum public website.
// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:circum/app/gifts/gift_request_policy.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../firebase_options.dart';

const _canonicalSenderAppUrl = 'https://circum-app-2797c.web.app';
const _canonicalRiderAppUrl = 'https://circum-rider-2797c.web.app';

class CircumPublicWebsiteApp extends StatefulWidget {
  const CircumPublicWebsiteApp({super.key});

  @override
  State<CircumPublicWebsiteApp> createState() => _CircumPublicWebsiteAppState();
}

class _CircumPublicWebsiteAppState extends State<CircumPublicWebsiteApp> {
  bool _darkMode = true;
  bool _authOpen = false;
  _PublicAuthMode _authMode = _PublicAuthMode.login;
  late CircumPublicRoute _route = _routeFromUri(Uri.base);

  @override
  void initState() {
    super.initState();
    _assertPublicSurfaceIntegrity();
    if (_isRiderEntry(Uri.base)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openExternal(_canonicalRiderAppUrl),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _CircumColors(_darkMode);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Circum',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Helvetica',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2563eb),
          brightness: _darkMode ? Brightness.dark : Brightness.light,
        ),
      ),
      home: Scaffold(
        backgroundColor: colors.background,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: _authOpen
              ? _PublicAuthEntry(
                  key: ValueKey('public-auth-${_authMode.name}'),
                  colors: colors,
                  mode: _authMode,
                  onModeChanged: (mode) => setState(() => _authMode = mode),
                  onClose: () => setState(() => _authOpen = false),
                  onAuthenticated: () => _openExternal(_canonicalSenderAppUrl),
                )
              : CircumPublicAppRoot(
                  key: ValueKey('public-${_route.name}'),
                  colors: colors,
                  darkMode: _darkMode,
                  route: _route,
                  onStart: () => _openExternal(_canonicalSenderAppUrl),
                  onLogin: () => _openAuth(_PublicAuthMode.login),
                  onSignup: () => _openAuth(_PublicAuthMode.signup),
                  onRider: () => _openExternal(_canonicalRiderAppUrl),
                  onHealthPlus: () =>
                      _openExternal('$_canonicalSenderAppUrl/health-plus'),
                  onGifts: () => _openRoute(CircumPublicRoute.gifts),
                  onBusiness: () => _openRoute(CircumPublicRoute.business),
                  onBusinessAccess: () =>
                      _openExternal('$_canonicalSenderAppUrl/business'),
                  onHome: () => _openRoute(CircumPublicRoute.landing),
                  onToggleTheme: () => setState(() => _darkMode = !_darkMode),
                ),
        ),
      ),
    );
  }

  void _openAuth(_PublicAuthMode mode) => setState(() {
        _authMode = mode;
        _authOpen = true;
      });

  void _openRoute(CircumPublicRoute route) => setState(() {
        _authOpen = false;
        _route = route;
        html.window.history.pushState(null, '', _pathForRoute(route));
      });

  void _openExternal(String url) => html.window.location.assign(url);
}

void _assertPublicSurfaceIntegrity() {
  assert(() {
    if (_canonicalSenderAppUrl == _canonicalRiderAppUrl) {
      throw StateError(
        'Public surface boundary violation: application hosts overlap.',
      );
    }
    return true;
  }());
}

bool _isRiderEntry(Uri uri) {
  final path = uri.path.toLowerCase().replaceAll(RegExp(r'/+$'), '');
  final app = uri.queryParameters['app']?.toLowerCase();
  return path == '/rider' || app == 'rider' || app == 'earn';
}

CircumPublicRoute _routeFromUri(Uri uri) => switch (uri.path.toLowerCase()) {
      '/gifts' => CircumPublicRoute.gifts,
      '/terms' => CircumPublicRoute.terms,
      '/privacy' => CircumPublicRoute.privacy,
      '/vanguard' => CircumPublicRoute.vanguard,
      '/business' => CircumPublicRoute.business,
      _ => CircumPublicRoute.landing,
    };

String _pathForRoute(CircumPublicRoute route) => switch (route) {
      CircumPublicRoute.landing => '/',
      CircumPublicRoute.gifts => '/gifts',
      CircumPublicRoute.terms => '/terms',
      CircumPublicRoute.privacy => '/privacy',
      CircumPublicRoute.vanguard => '/vanguard',
      CircumPublicRoute.business => '/business',
    };

const _spectrumGradient = [
  Color(0xffff8c00),
  Color(0xfff80032),
  Color(0xffff00a0),
  Color(0xff8c28ff),
  Color(0xff0023ff),
  Color(0xff19a0ff),
];

enum CircumPublicRoute {
  landing,
  gifts,
  terms,
  privacy,
  vanguard,
  business,
}

enum _PublicAuthMode { login, signup }

Future<void> _ensureCircumFirebaseReady() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app') {
      rethrow;
    }
  }
}

class CircumPublicAppRoot extends StatelessWidget {
  final _CircumColors colors;
  final bool darkMode;
  final CircumPublicRoute route;
  final VoidCallback onStart;
  final VoidCallback onLogin;
  final VoidCallback onSignup;
  final VoidCallback onRider;
  final VoidCallback onHealthPlus;
  final VoidCallback onGifts;
  final VoidCallback onBusiness;
  final VoidCallback onBusinessAccess;
  final VoidCallback onHome;
  final VoidCallback onToggleTheme;

  const CircumPublicAppRoot({
    super.key,
    required this.colors,
    required this.darkMode,
    required this.route,
    required this.onStart,
    required this.onLogin,
    required this.onSignup,
    required this.onRider,
    required this.onHealthPlus,
    required this.onGifts,
    required this.onBusiness,
    required this.onBusinessAccess,
    required this.onHome,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return switch (route) {
      CircumPublicRoute.gifts => _GiftsRequestPage(
          key: const ValueKey('public-gifts'),
          colors: colors,
          onBack: onHome,
        ),
      CircumPublicRoute.terms => _LegalDocumentPage(
          key: const ValueKey('public-terms'),
          colors: colors,
          title: 'Terms of Service',
          documentPath: '/legal/CIRCUM_Terms_of_Service.pdf',
          onBack: onHome,
        ),
      CircumPublicRoute.privacy => _LegalDocumentPage(
          key: const ValueKey('public-privacy'),
          colors: colors,
          title: 'Privacy Policy',
          documentPath: '/legal/CIRCUM_Privacy_Policy.pdf',
          onBack: onHome,
        ),
      CircumPublicRoute.vanguard => _VanguardExplainerPage(
          key: const ValueKey('public-vanguard'),
          onHome: onHome,
        ),
      CircumPublicRoute.business => _BusinessCommandPage(
          key: const ValueKey('public-business'),
          colors: colors,
          onHome: onHome,
          onAccess: onBusinessAccess,
        ),
      CircumPublicRoute.landing => _LandingPage(
          key: const ValueKey('public-landing'),
          colors: colors,
          darkMode: darkMode,
          onStart: onStart,
          onLogin: onLogin,
          onSignup: onSignup,
          onRider: onRider,
          onHealthPlus: onHealthPlus,
          onGifts: onGifts,
          onBusiness: onBusiness,
          onBusinessAccess: onBusinessAccess,
          onToggleTheme: onToggleTheme,
        ),
    };
  }
}

class _PublicAuthEntry extends StatefulWidget {
  final _CircumColors colors;
  final _PublicAuthMode mode;
  final ValueChanged<_PublicAuthMode> onModeChanged;
  final VoidCallback onClose;
  final VoidCallback onAuthenticated;

  const _PublicAuthEntry({
    super.key,
    required this.colors,
    required this.mode,
    required this.onModeChanged,
    required this.onClose,
    required this.onAuthenticated,
  });

  @override
  State<_PublicAuthEntry> createState() => _PublicAuthEntryState();
}

class _PublicAuthEntryState extends State<_PublicAuthEntry> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _rememberMe = true;
  bool _acceptTerms = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _showErrors = false;
  bool _busy = false;
  String? _message;

  bool get _isLogin => widget.mode == _PublicAuthMode.login;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final narrow = MediaQuery.sizeOf(context).width < 680;
    final emailError = !_showErrors
        ? null
        : !_looksLikeEmail(_email.text.trim())
            ? 'Enter a valid email address'
            : null;
    final passwordError = !_showErrors
        ? null
        : _password.text.isEmpty
            ? 'Password is required'
            : !_isLogin && _password.text.length < 6
                ? 'Use at least 6 characters'
                : null;
    final confirmError = !_showErrors || _isLogin
        ? null
        : _confirmPassword.text != _password.text
            ? 'Passwords do not match'
            : null;

    return Container(
      color: colors.appBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.8, -0.75),
                  radius: 1.1,
                  colors: [
                    const Color(0xff3b82f6).withValues(alpha: 0.22),
                    const Color(0xff0b1020).withValues(alpha: 0.9),
                    colors.appBackground,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                narrow ? 18 : 28,
                18,
                narrow ? 18 : 28,
                38,
              ),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: widget.onClose,
                        icon: Icon(Icons.arrow_back, color: colors.text),
                      ),
                      const SizedBox(width: 8),
                      Image.asset(
                        'assets/images/circum_wordmark.png',
                        width: 136,
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: narrow ? 28 : 52),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          padding: EdgeInsets.all(narrow ? 22 : 34),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.065),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xff3b82f6)
                                    .withValues(alpha: 0.16),
                                blurRadius: 50,
                                offset: const Offset(0, 26),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Welcome to Circum',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.dmSerifDisplay(
                                  color: colors.text,
                                  fontSize: narrow ? 38 : 48,
                                  height: 1.02,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Sign in to continue or create a new account.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: colors.mutedText,
                                  fontSize: 15,
                                  height: 1.45,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _PublicAuthModeSelector(
                                colors: colors,
                                mode: widget.mode,
                                onChanged: (mode) {
                                  setState(() {
                                    _showErrors = false;
                                    _message = null;
                                  });
                                  widget.onModeChanged(mode);
                                },
                              ),
                              const SizedBox(height: 24),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 240),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.04, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                                child: _isLogin
                                    ? _buildLoginForm(
                                        colors,
                                        emailError,
                                        passwordError,
                                      )
                                    : _buildSignupForm(
                                        colors,
                                        emailError,
                                        passwordError,
                                        confirmError,
                                      ),
                              ),
                              const SizedBox(height: 18),
                              FilledButton(
                                onPressed: _busy ? null : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xff3b82f6),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 18),
                                ),
                                child: Text(
                                  _busy
                                      ? 'Please wait...'
                                      : _isLogin
                                          ? 'Log in'
                                          : 'Create account',
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => widget.onModeChanged(
                                          _isLogin
                                              ? _PublicAuthMode.signup
                                              : _PublicAuthMode.login,
                                        ),
                                child: Text(
                                  _isLogin
                                      ? 'Create account'
                                      : 'Already have an account? Log in',
                                ),
                              ),
                              if (_message != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  _message!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colors.text,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                      child: Divider(color: colors.border)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      'or',
                                      style: TextStyle(
                                        color: colors.mutedText,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                      child: Divider(color: colors.border)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _PublicAuthSocialButton(
                                    colors: colors,
                                    icon: Icons.g_mobiledata,
                                    label: _isLogin
                                        ? 'Google'
                                        : 'Continue with Google',
                                    onPressed: _busy
                                        ? null
                                        : () => _providerSignIn('google'),
                                  ),
                                  _PublicAuthSocialButton(
                                    colors: colors,
                                    icon: Icons.apple,
                                    label: _isLogin
                                        ? 'Apple'
                                        : 'Continue with Apple',
                                    onPressed: _busy
                                        ? null
                                        : () => _providerSignIn('apple'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm(
    _CircumColors colors,
    String? emailError,
    String? passwordError,
  ) {
    return Column(
      key: const ValueKey('public-login'),
      children: [
        _PublicAuthField(
          colors: colors,
          controller: _email,
          label: 'Email',
          hint: 'you@email.com',
          keyboardType: TextInputType.emailAddress,
          errorText: emailError,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _PublicAuthField(
          colors: colors,
          controller: _password,
          label: 'Password',
          hint: 'Password',
          obscureText: !_showPassword,
          errorText: passwordError,
          onChanged: (_) => setState(() {}),
          suffixIcon: IconButton(
            tooltip: _showPassword ? 'Hide password' : 'Show password',
            onPressed: () => setState(() => _showPassword = !_showPassword),
            icon: Icon(
              _showPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: colors.mutedText,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _PublicCheckRow(
              colors: colors,
              label: 'Remember me',
              value: _rememberMe,
              onChanged: (value) => setState(() => _rememberMe = value),
            ),
            const Spacer(),
            TextButton(
              onPressed: _busy ? null : _resetPassword,
              child: const Text('Forgot password?'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignupForm(
    _CircumColors colors,
    String? emailError,
    String? passwordError,
    String? confirmError,
  ) {
    final firstNameError =
        _showErrors && _firstName.text.trim().isEmpty ? 'Required' : null;
    final lastNameError =
        _showErrors && _lastName.text.trim().isEmpty ? 'Required' : null;
    final phoneError =
        _showErrors && _phone.text.trim().isEmpty ? 'Phone is required' : null;
    return Column(
      key: const ValueKey('public-signup'),
      children: [
        Row(
          children: [
            Expanded(
              child: _PublicAuthField(
                colors: colors,
                controller: _firstName,
                label: 'First name',
                hint: 'First name',
                errorText: firstNameError,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PublicAuthField(
                colors: colors,
                controller: _lastName,
                label: 'Last name',
                hint: 'Last name',
                errorText: lastNameError,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PublicAuthField(
          colors: colors,
          controller: _email,
          label: 'Email',
          hint: 'you@email.com',
          keyboardType: TextInputType.emailAddress,
          errorText: emailError,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _PublicAuthField(
          colors: colors,
          controller: _phone,
          label: 'Phone number',
          hint: '+44 7000 000000',
          keyboardType: TextInputType.phone,
          errorText: phoneError,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _PublicAuthField(
          colors: colors,
          controller: _password,
          label: 'Password',
          hint: 'Create a password',
          obscureText: !_showPassword,
          errorText: passwordError,
          onChanged: (_) => setState(() {}),
          suffixIcon: IconButton(
            tooltip: _showPassword ? 'Hide password' : 'Show password',
            onPressed: () => setState(() => _showPassword = !_showPassword),
            icon: Icon(
              _showPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: colors.mutedText,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _PublicAuthField(
          colors: colors,
          controller: _confirmPassword,
          label: 'Confirm password',
          hint: 'Confirm password',
          obscureText: !_showConfirmPassword,
          errorText: confirmError,
          onChanged: (_) => setState(() {}),
          suffixIcon: IconButton(
            tooltip: _showConfirmPassword ? 'Hide password' : 'Show password',
            onPressed: () =>
                setState(() => _showConfirmPassword = !_showConfirmPassword),
            icon: Icon(
              _showConfirmPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: colors.mutedText,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: _PublicCheckRow(
            colors: colors,
            label: 'Accept Terms',
            value: _acceptTerms,
            onChanged: (value) => setState(() => _acceptTerms = value),
          ),
        ),
        if (_showErrors && !_acceptTerms) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Accept Terms to create your account.',
              style: GoogleFonts.inter(
                color: const Color(0xfff87171),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _showErrors = true;
      _message = null;
    });
    final email = _email.text.trim().toLowerCase();
    final valid = _looksLikeEmail(email) &&
        _password.text.isNotEmpty &&
        (_isLogin ||
            (_firstName.text.trim().isNotEmpty &&
                _lastName.text.trim().isNotEmpty &&
                _phone.text.trim().isNotEmpty &&
                _password.text.length >= 6 &&
                _password.text == _confirmPassword.text &&
                _acceptTerms));
    if (!valid) return;
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.setPersistence(
        _rememberMe ? Persistence.LOCAL : Persistence.SESSION,
      );
      final auth = FirebaseAuth.instance;
      final credential = _isLogin
          ? await auth.signInWithEmailAndPassword(
              email: email,
              password: _password.text,
            )
          : await auth.createUserWithEmailAndPassword(
              email: email,
              password: _password.text,
            );
      await _upsertSenderUser(credential.user, created: !_isLogin);
      widget.onAuthenticated();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _message = _authMessageFor(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _providerSignIn(String providerName) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final provider = providerName == 'apple'
          ? (OAuthProvider('apple.com')..setCustomParameters({'locale': 'en'}))
          : (GoogleAuthProvider()
            ..setCustomParameters({'prompt': 'select_account'}));
      final credential = await FirebaseAuth.instance.signInWithPopup(provider);
      await _upsertSenderUser(credential.user);
      widget.onAuthenticated();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _message = _authMessageFor(error));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _message = 'This sign-in option is not available here yet.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim().toLowerCase();
    setState(() {
      _showErrors = true;
      _message = null;
    });
    if (!_looksLikeEmail(email)) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() => _message = 'Password reset email sent.');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _message = _authMessageFor(error));
    }
  }

  Future<void> _upsertSenderUser(User? user, {bool created = false}) async {
    if (user == null) {
      throw FirebaseAuthException(code: 'sender-auth-no-user');
    }
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'email': user.email,
      'displayName': user.displayName,
      if (_firstName.text.trim().isNotEmpty)
        'firstName': _firstName.text.trim(),
      if (_lastName.text.trim().isNotEmpty) 'lastName': _lastName.text.trim(),
      if (_firstName.text.trim().isNotEmpty || _lastName.text.trim().isNotEmpty)
        'fullName': [_firstName.text.trim(), _lastName.text.trim()]
            .where((value) => value.isNotEmpty)
            .join(' '),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      'role': 'user',
      'roles': ['sender'],
      'userType': 'sender',
      'status': 'active',
      'source': 'public_sender_web',
      if (created) 'termsAcceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await user.getIdToken(true);
  }

  String _authMessageFor(FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-email' => 'Enter a valid email address.',
      'weak-password' => 'Use a stronger password.',
      'email-already-in-use' => 'That email already has a Circum account.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' =>
        'Log in failed. Check the email and password.',
      'popup-closed-by-user' => 'Sign-in was cancelled.',
      _ => 'Authentication failed (${error.code}).',
    };
  }

  bool _looksLikeEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
}

class _PublicAuthModeSelector extends StatelessWidget {
  final _CircumColors colors;
  final _PublicAuthMode mode;
  final ValueChanged<_PublicAuthMode> onChanged;

  const _PublicAuthModeSelector({
    required this.colors,
    required this.mode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          _PublicAuthTab(
            colors: colors,
            label: 'Log in',
            active: mode == _PublicAuthMode.login,
            onTap: () => onChanged(_PublicAuthMode.login),
          ),
          _PublicAuthTab(
            colors: colors,
            label: 'Create account',
            active: mode == _PublicAuthMode.signup,
            onTap: () => onChanged(_PublicAuthMode.signup),
          ),
        ],
      ),
    );
  }
}

class _PublicAuthTab extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PublicAuthTab({
    required this.colors,
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
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: active ? const Color(0xff3b82f6) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: active ? Colors.white : colors.mutedText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicAuthField extends StatelessWidget {
  final _CircumColors colors;
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final Widget? suffixIcon;

  const _PublicAuthField({
    required this.colors,
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.errorText,
    required this.onChanged,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: label,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onChanged: onChanged,
        style: GoogleFonts.inter(
          color: colors.text,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.07),
          labelStyle: TextStyle(color: colors.mutedText),
          hintStyle: TextStyle(color: colors.mutedText.withValues(alpha: 0.7)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xff3b82f6)),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xfff87171)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xfff87171)),
          ),
        ),
      ),
    );
  }
}

class _PublicCheckRow extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PublicCheckRow({
    required this.colors,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: value,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: value ? const Color(0xff3b82f6) : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: colors.border),
                ),
                child: value
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : null,
              ),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  color: colors.text,
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

class _PublicAuthSocialButton extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _PublicAuthSocialButton({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.text,
          side: BorderSide(color: colors.border),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class _LandingPage extends StatelessWidget {
  final _CircumColors colors;
  final bool darkMode;
  final VoidCallback onStart;
  final VoidCallback onLogin;
  final VoidCallback onSignup;
  final VoidCallback onRider;
  final VoidCallback onHealthPlus;
  final VoidCallback? onGifts;
  final VoidCallback onBusiness;
  final VoidCallback onBusinessAccess;
  final VoidCallback onToggleTheme;

  const _LandingPage({
    super.key,
    required this.colors,
    required this.darkMode,
    required this.onStart,
    required this.onLogin,
    required this.onSignup,
    required this.onRider,
    required this.onHealthPlus,
    this.onGifts,
    required this.onBusiness,
    required this.onBusinessAccess,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _LandingNav(
            colors: colors,
            darkMode: darkMode,
            onStart: onStart,
            onLogin: onLogin,
            onSignup: onSignup,
            onRider: onRider,
            onHealthPlus: onHealthPlus,
            onGifts: onGifts,
            onBusiness: onBusiness,
            onToggleTheme: onToggleTheme,
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors.dark
                    ? const [
                        Color(0xff050816),
                        Color(0xff251047),
                        Color(0xff1d4ed8),
                        Color(0xff061826),
                      ]
                    : const [
                        Color(0xffffffff),
                        Color(0xfffff4de),
                        Color(0xffffe5f3),
                        Color(0xffebe8ff),
                        Color(0xffdff8ff),
                        Color(0xffffffff),
                      ],
                stops: colors.dark
                    ? const [0, 0.36, 0.72, 1]
                    : const [0, 0.16, 0.39, 0.62, 0.84, 1],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(22, 58, 22, 46),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _SpectrumSweepPainter(dark: colors.dark),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Send anything across town.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: MediaQuery.sizeOf(context).width < 680
                                ? 48
                                : 76,
                            height: 1.02,
                            color: colors.dark
                                ? Colors.white
                                : const Color(0xff111827),
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(
                                color: colors.dark
                                    ? Colors.black.withOpacity(0.32)
                                    : Colors.white.withOpacity(0.78),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Book trusted riders for parcels, prescriptions, documents, and larger items. See the price, track the parcel, and stay in control.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.mutedText,
                      fontSize:
                          MediaQuery.sizeOf(context).width < 680 ? 18 : 22,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _PillButton(
                        label: 'Send a Parcel',
                        icon: Icons.arrow_forward,
                        dark: true,
                        onPressed: onStart,
                      ),
                      _PillButton(
                        label: 'Earn as a Rider',
                        icon: Icons.two_wheeler,
                        dark: false,
                        onPressed: onRider,
                      ),
                      _PillButton(
                        label: 'Get started with Health+',
                        icon: Icons.health_and_safety,
                        dark: false,
                        onPressed: onHealthPlus,
                      ),
                    ],
                  ),
                  const SizedBox(height: 58),
                  _HeroMockup(colors: colors, onStart: onStart),
                ],
              ),
            ),
          ),
          _FeatureBand(colors: colors),
          _VanguardLandingBand(colors: colors),
          _BusinessLandingBand(
            colors: colors,
            onBusinessLogin: onBusiness,
            onCreateBusiness: onBusinessAccess,
          ),
          _HealthPlusLandingBand(colors: colors, onHealthPlus: onHealthPlus),
          _LandingFooter(colors: colors),
        ],
      ),
    );
  }
}

List<String> _interests(Map<String, dynamic> item) =>
    (item['interests'] as List? ?? const [])
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList();

String _adminDateText(dynamic value) {
  DateTime? date;
  if (value is Timestamp) date = value.toDate();
  if (value is DateTime) date = value;
  if (value is String) date = DateTime.tryParse(value);
  if (date == null) return 'Not yet';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _GiftStoryOutputDraft {
  final String senderName;
  final String recipientName;
  final String relationship;
  final String occasion;
  final String story;
  final List<String> interests;
  final String? audioUrl;
  final List<String> photoUrls;
  final bool deliveryCompleted;
  final String? renderedVideoUrl;

  const _GiftStoryOutputDraft({
    required this.senderName,
    required this.recipientName,
    required this.relationship,
    required this.occasion,
    required this.story,
    required this.interests,
    this.audioUrl,
    required this.photoUrls,
    required this.deliveryCompleted,
    this.renderedVideoUrl,
  });
}

List<String> _giftStringList(dynamic value) {
  if (value is Iterable) {
    return value
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}

String _giftStorySharePrivacy(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('-', '_');
  if (const ['public', 'unlisted', 'private'].contains(normalized)) {
    return normalized;
  }
  return 'private';
}

class _LandingNav extends StatelessWidget {
  final _CircumColors colors;
  final bool darkMode;
  final VoidCallback onStart;
  final VoidCallback onLogin;
  final VoidCallback onSignup;
  final VoidCallback onRider;
  final VoidCallback onHealthPlus;
  final VoidCallback? onGifts;
  final VoidCallback onBusiness;
  final VoidCallback onToggleTheme;

  const _LandingNav({
    required this.colors,
    required this.darkMode,
    required this.onStart,
    required this.onLogin,
    required this.onSignup,
    required this.onRider,
    required this.onHealthPlus,
    this.onGifts,
    required this.onBusiness,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Row(
            children: [
              Image.asset(
                'assets/images/circum_wordmark.png',
                width: 136,
                height: 32,
                fit: BoxFit.contain,
              ),
              const Spacer(),
              IconButton(
                tooltip: darkMode ? 'Light mode' : 'Dark mode',
                onPressed: onToggleTheme,
                icon: Icon(
                  darkMode ? Icons.light_mode : Icons.dark_mode,
                  color: colors.text,
                ),
              ),
              const SizedBox(width: 8),
              if (width >= 560)
                TextButton(
                  onPressed: onRider,
                  child: Text(
                    'Rider',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (width >= 680)
                TextButton(
                  onPressed: onHealthPlus,
                  child: Text(
                    'Health+',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (width >= 720)
                TextButton(
                  onPressed: onBusiness,
                  child: Text(
                    'Business',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (width >= 520)
                IconButton(
                  tooltip: 'Business',
                  onPressed: onBusiness,
                  icon:
                      Icon(Icons.business_center_outlined, color: colors.text),
                )
              else
                IconButton(
                  tooltip: 'Business',
                  onPressed: onBusiness,
                  icon:
                      Icon(Icons.business_center_outlined, color: colors.text),
                ),
              if (onGifts != null && width >= 760)
                TextButton.icon(
                  onPressed: onGifts,
                  icon: const Icon(Icons.card_giftcard, size: 18),
                  label: Text(
                    'Gifts',
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (onGifts != null)
                IconButton(
                  tooltip: 'Gifts',
                  onPressed: onGifts,
                  icon: Icon(Icons.card_giftcard, color: colors.text),
                ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onLogin,
                child: Text(
                  'Log in',
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              OutlinedButton(
                onPressed: onSignup,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.text,
                  side: BorderSide(color: colors.border),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                ),
                child: const Text('Sign up'),
              ),
              const SizedBox(width: 8),
              if (width < 520)
                IconButton.filled(
                  tooltip: 'Book delivery',
                  onPressed: onStart,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: colors.text,
                    foregroundColor: colors.inverseText,
                  ),
                )
              else
                FilledButton(
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.text,
                    foregroundColor: colors.inverseText,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('Send a Parcel'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpectrumSweepPainter extends CustomPainter {
  final bool dark;

  const _SpectrumSweepPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final sweepRect = Rect.fromLTWH(
      size.width * 0.02,
      size.height * 0.08,
      size.width * 0.96,
      size.height * 0.84,
    );
    final spectrum = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: _spectrumGradient,
      ).createShader(sweepRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = dark ? 22 : 18
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, dark ? 28 : 22);

    final path = Path()
      ..moveTo(sweepRect.left, sweepRect.center.dy + sweepRect.height * 0.16)
      ..cubicTo(
        sweepRect.left + sweepRect.width * 0.22,
        sweepRect.top - sweepRect.height * 0.12,
        sweepRect.left + sweepRect.width * 0.44,
        sweepRect.bottom + sweepRect.height * 0.14,
        sweepRect.left + sweepRect.width * 0.62,
        sweepRect.center.dy,
      )
      ..cubicTo(
        sweepRect.left + sweepRect.width * 0.78,
        sweepRect.top - sweepRect.height * 0.1,
        sweepRect.right - sweepRect.width * 0.12,
        sweepRect.bottom + sweepRect.height * 0.08,
        sweepRect.right,
        sweepRect.center.dy - sweepRect.height * 0.16,
      );

    canvas.drawPath(path, spectrum);
  }

  @override
  bool shouldRepaint(covariant _SpectrumSweepPainter oldDelegate) {
    return oldDelegate.dark != dark;
  }
}

class _HeroMockup extends StatelessWidget {
  final _CircumColors colors;
  final VoidCallback onStart;

  const _HeroMockup({required this.colors, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final map = _MiniMap(colors: colors, active: true);
        final panel = _GlassPanel(
          colors: colors,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _LogoTile(colors: colors),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your rider is on the way',
                          style: TextStyle(
                            color: colors.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Bike courier arriving in 8 min',
                          style: TextStyle(
                            color: colors.mutedText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _RouteRow(
                colors: colors,
                from: 'Pickup address',
                to: 'Drop-off address',
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MetricPill(
                      colors: colors,
                      label: 'ETA',
                      value: '14 min',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MetricPill(
                      colors: colors,
                      label: 'Quote',
                      value: '£9.80',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Start a delivery'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.text,
                    foregroundColor: colors.inverseText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(colors.dark ? 0.32 : 0.08),
                blurRadius: 36,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: wide
              ? Row(
                  children: [
                    Expanded(flex: 6, child: map),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: panel),
                  ],
                )
              : Column(children: [map, const SizedBox(height: 16), panel]),
        );
      },
    );
  }
}

class _FeatureBand extends StatelessWidget {
  final _CircumColors colors;

  const _FeatureBand({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: colors.band,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 70),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth < 760 ? 1 : 3;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                mainAxisSpacing: 18,
                crossAxisSpacing: 18,
                childAspectRatio: cols == 1 ? 2.1 : 1.05,
                children: [
                  _FeatureCard(
                    colors: colors,
                    icon: Icons.tune,
                    tint: const Color(0xffdbeafe),
                    title: 'Iris matching',
                    body:
                        'Tell Iris what you are sending and it helps choose the right rider, vehicle, route, and price.',
                  ),
                  _FeatureCard(
                    colors: colors,
                    icon: Icons.verified_user_outlined,
                    tint: const Color(0xffdcfce7),
                    title: 'Built-in reassurance',
                    body:
                        'Follow the journey with live location, rider details, status updates, and delivery proof.',
                  ),
                  _FeatureCard(
                    colors: colors,
                    icon: Icons.bolt,
                    tint: const Color(0xffede9fe),
                    title: 'Ready when you are',
                    body:
                        'Send the job to nearby riders and choose the option that fits the delivery.',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

Future<double> _fetchRothBalanceForUser(User? user) async {
  if (user == null) return 0;
  final walletId = (user.email ?? user.uid).trim().toLowerCase();
  final snapshot = await FirebaseFirestore.instance
      .collection('wallets')
      .doc(walletId)
      .get();
  final data = snapshot.data() ?? const <String, dynamic>{};
  return ((data['balance'] ?? data['rothCredit']) as num?)?.toDouble() ?? 0;
}

class _HealthChip extends StatelessWidget {
  final _CircumColors? colors;
  final String label;

  const _HealthChip({this.colors, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = this.colors;
    if (colors == null) {
      return Chip(
        label: Text(label),
        visualDensity: VisualDensity.compact,
        backgroundColor: const Color(0xffecfdf5),
        labelStyle: const TextStyle(
          color: Color(0xff166534),
          fontWeight: FontWeight.w800,
        ),
        side: BorderSide.none,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            colors.adminAccent.withValues(alpha: 0.18),
            colors.field.withValues(alpha: 0.72),
          ],
        ),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.text,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AddressSuggestion {
  final String displayAddress;
  final double? lat;
  final double? lng;
  final double confidence;
  final String provider;
  final String sourceInput;
  final String? placeId;
  final String? searchText;
  final String? category;
  final Map<String, String> components;

  const _AddressSuggestion({
    required this.displayAddress,
    this.lat,
    this.lng,
    required this.confidence,
    required this.provider,
    required this.sourceInput,
    this.placeId,
    this.searchText,
    this.category,
    this.components = const {},
  });

  bool get isPopularPlace => provider == 'circum_popular_place';
  bool get isExactTypedAddress => provider == 'circum_exact_address_input';

  _ValidatedAddress toValidatedAddress() {
    final resolvedLat = lat ?? 0;
    final resolvedLng = lng ?? 0;
    return _ValidatedAddress(
      rawInput: sourceInput,
      displayAddress: displayAddress,
      postcode: components['postcode'] ?? _extractUkPostcode(displayAddress),
      lat: resolvedLat,
      lng: resolvedLng,
      confidence: confidence,
      provider: provider,
      locationId: placeId ??
          _stableLocationId(displayAddress, resolvedLat, resolvedLng),
      placeId: placeId,
      buildingNumber: components['buildingNumber'],
      street: components['street'],
      city: components['city'],
      county: components['county'],
      country: components['country'],
    );
  }
}

class _ValidatedAddress {
  final String rawInput;
  final String displayAddress;
  final String? postcode;
  final double lat;
  final double lng;
  final double confidence;
  final String provider;
  final String locationId;
  final String? placeId;
  final String? buildingNumber;
  final String? street;
  final String? city;
  final String? county;
  final String? country;

  const _ValidatedAddress({
    required this.rawInput,
    required this.displayAddress,
    required this.postcode,
    required this.lat,
    required this.lng,
    required this.confidence,
    required this.provider,
    required this.locationId,
    this.placeId,
    this.buildingNumber,
    this.street,
    this.city,
    this.county,
    this.country,
  });

  bool get hasCoordinates => _coordinatesAreUsable(lat, lng);

  bool get isVerified => hasCoordinates && confidence >= 0.8;

  String get confidenceBand {
    if (confidence >= 0.98) return 'exact_match';
    if (confidence >= 0.9) return 'high';
    if (confidence >= 0.8) return 'medium';
    return 'low';
  }

  String get compactDisplay {
    final primary = [buildingNumber, street]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(' ');
    final locality = [city, postcode]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .join(' ');
    if (primary.isNotEmpty && locality.isNotEmpty) return '$primary\n$locality';
    if (street?.trim().isNotEmpty == true &&
        postcode?.trim().isNotEmpty == true) {
      return '${street!.trim()}\n${postcode!.trim()}';
    }
    return displayAddress;
  }

  Map<String, dynamic> toJson() => {
        'rawInput': rawInput,
        'displayAddress': displayAddress,
        'formattedAddress': displayAddress,
        'addressLine1': [buildingNumber, street]
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .join(' '),
        'postcode': postcode,
        'cityTown': city,
        'lat': lat,
        'lng': lng,
        'geocodeConfidence': confidence,
        'confidenceBand': confidenceBand,
        'validationStatus': isVerified ? 'verified' : 'requires_confirmation',
        'addressSource': provider,
        'provider': provider,
        'locationId': locationId,
        if (placeId != null) 'placeId': placeId,
        if (buildingNumber != null) 'buildingNumber': buildingNumber,
        if (street != null) 'street': street,
        if (city != null) 'city': city,
        if (county != null) 'county': county,
        if (country != null) 'country': country,
      };

  Map<String, dynamic> toPositionMap() => {
        'geopoint': GeoPoint(lat, lng),
        'lat': lat,
        'lng': lng,
        'geocodeConfidence': confidence,
        'locationId': locationId,
        if (placeId != null) 'placeId': placeId,
        'provider': provider,
      };
}

String? _extractUkPostcode(String address) {
  final match = RegExp(
    r'\b([A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2})\b',
    caseSensitive: false,
  ).firstMatch(address);
  return match?.group(1)?.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
}

bool _hasSpecificAddressDetail(String address) {
  final lower = address.toLowerCase();
  if (_extractUkPostcode(address) != null) return true;
  if (RegExp(r'\b(flat|apartment|apt|unit|suite|room|floor|building)\b')
      .hasMatch(lower)) {
    return true;
  }
  if (RegExp(r'\b\d+[a-z]?\b').hasMatch(lower) &&
      RegExp(r'\b(street|st|road|rd|avenue|ave|lane|ln|drive|dr|close|court|way|place|pl|mews|gardens|square|terrace)\b')
          .hasMatch(lower)) {
    return true;
  }
  return false;
}

String _stableLocationId(String address, double lat, double lng) {
  final normalized = address.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '-',
      );
  return '${normalized.substring(0, math.min(normalized.length, 48))}'
      '-${lat.toStringAsFixed(4)}-${lng.toStringAsFixed(4)}';
}

String _cityForAddress(String value) {
  final lower = value.toLowerCase();
  for (final city in _ukCityCoordinates.keys) {
    if (lower.contains(city.toLowerCase())) return city;
  }
  final postcode = _extractUkPostcode(value);
  if (postcode != null) {
    final outward = _postcodeOutward(postcode);
    if (outward.startsWith('CR')) return 'Croydon';
    if (outward.startsWith('SE') ||
        outward.startsWith('SW') ||
        outward.startsWith('E') ||
        outward.startsWith('N') ||
        outward.startsWith('NW') ||
        outward.startsWith('W')) {
      return 'London';
    }
  }
  return 'London';
}

bool _coordinatesAreUsable(double lat, double lng) {
  if (!lat.isFinite || !lng.isFinite) return false;
  if (lat == 0 || lng == 0) return false;
  return lat >= 49 && lat <= 61 && lng >= -9 && lng <= 2;
}

String _postcodeOutward(String postcode) {
  return postcode
      .toUpperCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .split(' ')
      .first;
}

(double, double)? _postcodeCoordinatesForAddress(String address) {
  final postcode = _extractUkPostcode(address);
  if (postcode == null) return null;
  final outward = _postcodeOutward(postcode);
  final area = RegExp(r'^[A-Z]+').firstMatch(outward)?.group(0);
  return _ukPostcodeCoordinates[outward] ??
      (area == null ? null : _ukPostcodeCoordinates[area]);
}

String _firstName(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text == 'null') return '';
  return text.split(RegExp(r'\s+')).first;
}

class _MiniMap extends StatelessWidget {
  final _CircumColors colors;
  final bool active;

  const _MiniMap({required this.colors, required this.active});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.65,
      child: CustomPaint(
        painter: _MapPainter(colors: colors, active: active),
        child: Stack(
          children: [
            Positioned(
              left: 22,
              bottom: 20,
              child: _MapPin(colors: colors, label: 'Pickup'),
            ),
            Positioned(
              right: 24,
              top: 22,
              child: _MapPin(colors: colors, label: 'Drop-off'),
            ),
            Positioned(
              left: active ? 175 : 132,
              top: active ? 78 : 98,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xff2563eb),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x552563eb),
                      blurRadius: 18,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.two_wheeler,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final _CircumColors colors;
  final bool active;

  _MapPainter({required this.colors, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = LinearGradient(
        colors: colors.dark
            ? [const Color(0xff111827), const Color(0xff1e293b)]
            : [const Color(0xffeff6ff), const Color(0xfff8fafc)],
      ).createShader(Offset.zero & size);
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(24),
    );
    canvas.drawRRect(rect, background);

    final road = Paint()
      ..color = colors.dark ? const Color(0xff334155) : const Color(0xffffffff)
      ..strokeWidth = 18
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.06, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.46,
        size.width * 0.48,
        size.height * 0.58,
      )
      ..quadraticBezierTo(
        size.width * 0.68,
        size.height * 0.70,
        size.width * 0.90,
        size.height * 0.18,
      );
    canvas.drawPath(path, road);

    final route = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: _spectrumGradient,
      ).createShader(Offset.zero & size)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, route);

    final grid = Paint()
      ..color = colors.dark
          ? Colors.white.withOpacity(0.04)
          : Colors.black.withOpacity(0.04)
      ..strokeWidth = 1;
    for (double x = 30; x < size.width; x += 52) {
      canvas.drawLine(Offset(x, 0), Offset(x - 40, size.height), grid);
    }
    for (double y = 24; y < size.height; y += 48) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 28), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) {
    return oldDelegate.colors.dark != colors.dark ||
        oldDelegate.active != active;
  }
}

class _MapPin extends StatelessWidget {
  final _CircumColors colors;
  final String label;

  const _MapPin({required this.colors, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.panel.withOpacity(0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.text,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AddressField extends StatefulWidget {
  final _CircumColors colors;
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool pharmacyMode;
  final bool verified;
  final ValueChanged<_ValidatedAddress>? onSelected;
  final ValueChanged<String>? onEdited;
  final String verifiedMessage;
  final bool glassStyle;
  final bool enableFreeLookup;

  const _AddressField({
    required this.colors,
    required this.icon,
    required this.label,
    required this.controller,
    this.pharmacyMode = false,
    this.verified = false,
    this.onSelected,
    this.onEdited,
    this.verifiedMessage = 'Verified address selected',
    this.glassStyle = false,
    this.enableFreeLookup = false,
  });

  @override
  State<_AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<_AddressField> {
  List<_AddressSuggestion> _suggestions = const [];
  final FocusNode _focusNode = FocusNode();
  bool _selectingSuggestion = false;
  bool _loadingSuggestions = false;
  bool _resolvingSuggestion = false;
  String? _suggestionError;
  int _suggestionRequest = 0;
  Timer? _suggestionDebounce;
  late final String _addressSearchSessionToken =
      '${DateTime.now().millisecondsSinceEpoch}-${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateSuggestions);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateSuggestions);
    _suggestionDebounce?.cancel();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus || widget.controller.text.trim().isNotEmpty) {
      return;
    }
    setState(() => _suggestions = _initialPopularSuggestions());
  }

  List<_AddressSuggestion> _initialPopularSuggestions() {
    final places = widget.pharmacyMode
        ? _circumPopularPlaces.where(
            (place) => const {'hospital', 'pharmacy', 'nhs facility'}
                .contains(place.category),
          )
        : _circumPopularPlaces.where(
            (place) => const {'station', 'airport', 'landmark'}
                .contains(place.category),
          );
    return places
        .take(4)
        .map(
          (place) => _AddressSuggestion(
            displayAddress: place.displayName,
            lat: place.lat,
            lng: place.lng,
            confidence: 0.98,
            provider: 'circum_popular_place',
            sourceInput: place.displayName,
            searchText: place.formattedAddress,
            category: place.category,
          ),
        )
        .toList(growable: false);
  }

  void _updateSuggestions() {
    if (_selectingSuggestion) return;
    _suggestionDebounce?.cancel();
    final value = widget.controller.text.trim();
    final requestId = ++_suggestionRequest;
    if (value.length < 3) {
      if (mounted) {
        setState(
          () => _suggestions = value.isEmpty && _focusNode.hasFocus
              ? _initialPopularSuggestions()
              : const [],
        );
      }
      return;
    }
    if (!widget.enableFreeLookup || value.length < 5) {
      final next = [
        ..._popularPlaceSuggestions(value),
        ..._localAddressSuggestions(value),
      ].take(8).toList(growable: false);
      if (mounted) {
        setState(() {
          _suggestions = next;
          _loadingSuggestions = false;
          _suggestionError = null;
        });
      }
      return;
    }
    setState(() {
      _loadingSuggestions = true;
      _suggestionError = null;
    });
    _suggestionDebounce = Timer(const Duration(milliseconds: 450), () {
      _buildAddressSuggestions(value).then((next) {
        if (!mounted || requestId != _suggestionRequest) return;
        setState(() {
          _suggestions = next;
          _loadingSuggestions = false;
        });
      });
    });
  }

  Future<List<_AddressSuggestion>> _buildAddressSuggestions(
    String value,
  ) async {
    if (value.length < 3) return const [];
    final clean = value.replaceAll(RegExp(r'\s+'), ' ');
    if (clean.toLowerCase().contains('united kingdom')) return const [];
    final popular = _popularPlaceSuggestions(clean);
    final freeLookup = widget.enableFreeLookup && clean.length >= 5
        ? await _freeUkAddressSearch(clean)
        : const <_AddressSuggestion>[];
    final exactTyped = _exactTypedAddressSuggestion(
      clean,
      [...freeLookup, ...popular],
    );
    final combined = <_AddressSuggestion>[
      if (exactTyped != null) exactTyped,
      ...popular,
      ...freeLookup.where(
        (suggestion) => !popular.any(
          (place) => _sameSuggestionText(
            place.displayAddress,
            suggestion.displayAddress,
          ),
        ),
      ),
    ];
    if (combined.isNotEmpty) return combined.take(8).toList(growable: false);
    return _localAddressSuggestions(clean);
  }

  _AddressSuggestion? _exactTypedAddressSuggestion(
    String clean,
    List<_AddressSuggestion> support,
  ) {
    if (!_hasSpecificAddressDetail(clean)) return null;
    final supported = support
        .where((suggestion) =>
            suggestion.lat != null &&
            suggestion.lng != null &&
            _coordinatesAreUsable(suggestion.lat!, suggestion.lng!))
        .toList(growable: false);
    final postcode = _extractUkPostcode(clean);
    final postcodeCoords = _postcodeCoordinatesForAddress(clean);
    final lat = supported.isNotEmpty ? supported.first.lat : postcodeCoords?.$1;
    final lng = supported.isNotEmpty ? supported.first.lng : postcodeCoords?.$2;
    if (lat == null || lng == null || !_coordinatesAreUsable(lat, lng)) {
      return null;
    }
    final inheritedComponents = supported.isNotEmpty
        ? supported.first.components
        : const <String, String>{};
    return _AddressSuggestion(
      displayAddress: clean,
      lat: lat,
      lng: lng,
      confidence: supported.isNotEmpty ? 0.88 : 0.8,
      provider: 'circum_exact_address_input',
      sourceInput: clean,
      placeId: _stableLocationId(clean, lat, lng),
      components: {
        ...inheritedComponents,
        if (postcode != null) 'postcode': postcode,
      },
    );
  }

  List<_AddressSuggestion> _popularPlaceSuggestions(String clean) {
    final typed = _normalizePlaceQuery(clean);
    if (typed.length < 3) return const [];
    return _circumPopularPlaces
        .where((place) => place.matches(typed))
        .map(
          (place) => _AddressSuggestion(
            displayAddress: place.displayName,
            lat: place.lat,
            lng: place.lng,
            confidence: 0.98,
            provider: 'circum_popular_place',
            sourceInput: clean,
            searchText: place.formattedAddress,
            category: place.category,
          ),
        )
        .take(4)
        .toList(growable: false);
  }

  List<_AddressSuggestion> _localAddressSuggestions(String clean) {
    final typed = clean.toLowerCase();
    final seeded = _ukAddressSuggestionSeeds.entries
        .where((entry) {
          final lower = entry.key.toLowerCase();
          final words = typed.split(' ').where((word) => word.isNotEmpty);
          return words.every(lower.contains);
        })
        .map(
          (entry) => _AddressSuggestion(
            displayAddress: entry.key,
            lat: entry.value.$1,
            lng: entry.value.$2,
            confidence: 0.96,
            provider: 'circum_seeded_geocoder',
            sourceInput: clean,
          ),
        )
        .take(4)
        .toList(growable: false);
    if (seeded.isNotEmpty) return seeded;
    final coords = _postcodeCoordinatesForAddress(clean);
    if (coords == null) return const [];
    final city = _cityForAddress(clean);
    if (widget.pharmacyMode) {
      return [
        _AddressSuggestion(
          displayAddress: '$clean Pharmacy, High Street, $city, United Kingdom',
          lat: coords.$1,
          lng: coords.$2,
          confidence: 0.82,
          provider: 'circum_postcode_geocoder',
          sourceInput: clean,
        ),
        _AddressSuggestion(
          displayAddress: '$clean, Pharmacy Counter, $city, United Kingdom',
          lat: coords.$1,
          lng: coords.$2,
          confidence: 0.8,
          provider: 'circum_postcode_geocoder',
          sourceInput: clean,
        ),
      ];
    }
    return [
      _AddressSuggestion(
        displayAddress: '$clean, $city, United Kingdom',
        lat: coords.$1,
        lng: coords.$2,
        confidence: 0.82,
        provider: 'circum_postcode_geocoder',
        sourceInput: clean,
      ),
      _AddressSuggestion(
        displayAddress: '$clean, United Kingdom',
        lat: coords.$1,
        lng: coords.$2,
        confidence: 0.8,
        provider: 'circum_postcode_geocoder',
        sourceInput: clean,
      ),
    ];
  }

  Future<List<_AddressSuggestion>> _freeUkAddressSearch(
    String input,
  ) async {
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('searchFreeUkAddresses')
          .call({
        'query': input,
        'sessionToken': _addressSearchSessionToken,
      }).timeout(
        const Duration(seconds: 5),
      );
      final body = Map<String, dynamic>.from(response.data as Map);
      if ('${body['status']}' != 'OK') return const [];
      final results = body['results'] as List<dynamic>? ?? const [];
      return results
          .whereType<Map<String, dynamic>>()
          .map((result) {
            final components = result['components'] is Map
                ? Map<String, String>.from(
                    (result['components'] as Map).map(
                      (key, value) => MapEntry('$key', '$value'),
                    ),
                  )
                : const <String, String>{};
            return _AddressSuggestion(
              displayAddress: '${result['displayAddress'] ?? ''}',
              lat: (result['lat'] as num?)?.toDouble(),
              lng: (result['lng'] as num?)?.toDouble(),
              confidence: (result['confidence'] as num?)?.toDouble() ?? 0.84,
              provider: 'openstreetmap_nominatim',
              sourceInput: input,
              placeId: '${result['locationId'] ?? ''}'.trim().isEmpty
                  ? null
                  : '${result['locationId']}',
              components: components,
            );
          })
          .where((suggestion) => suggestion.displayAddress.trim().isNotEmpty)
          .take(6)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<_AddressSuggestion?> _resolvePopularPlace(
    _AddressSuggestion suggestion,
  ) async {
    final query = suggestion.searchText ?? suggestion.displayAddress;
    final predictions = await _freeUkAddressSearch(query);
    if (predictions.isNotEmpty) {
      return predictions.first;
    }
    if (suggestion.lat != null &&
        suggestion.lng != null &&
        _coordinatesAreUsable(suggestion.lat!, suggestion.lng!)) {
      return _AddressSuggestion(
        displayAddress: suggestion.searchText ?? suggestion.displayAddress,
        lat: suggestion.lat,
        lng: suggestion.lng,
        confidence: 0.97,
        provider: 'circum_popular_place',
        sourceInput: suggestion.sourceInput,
        placeId: suggestion.placeId,
        searchText: suggestion.searchText,
        category: suggestion.category,
      );
    }
    return null;
  }

  Future<void> _selectSuggestion(_AddressSuggestion suggestion) async {
    if (_resolvingSuggestion) return;
    setState(() {
      _resolvingSuggestion = true;
      _suggestionError = null;
    });
    final resolved = suggestion.isPopularPlace
        ? await _resolvePopularPlace(suggestion)
        : suggestion;
    if (!mounted) return;
    if (resolved == null || !resolved.toValidatedAddress().hasCoordinates) {
      setState(() {
        _resolvingSuggestion = false;
        _suggestionError =
            'Could not verify this place. Try a different suggestion or enter the address manually.';
      });
      return;
    }
    _selectingSuggestion = true;
    widget.controller.text = resolved.displayAddress;
    widget.controller.selection = TextSelection.collapsed(
      offset: resolved.displayAddress.length,
    );
    _selectingSuggestion = false;
    widget.onSelected?.call(resolved.toValidatedAddress());
    setState(() {
      _suggestions = const [];
      _resolvingSuggestion = false;
      _suggestionError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final inputDecoration = widget.glassStyle
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [
                colors.adminAccent.withValues(alpha: 0.16),
                colors.field.withValues(alpha: 0.76),
              ],
            ),
            border: Border.all(
              color: widget.verified
                  ? colors.success.withValues(alpha: 0.46)
                  : colors.adminAccent.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.adminGlow.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: inputDecoration,
          padding: widget.glassStyle
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
              : EdgeInsets.zero,
          child: TextField(
            focusNode: _focusNode,
            controller: widget.controller,
            onChanged: (value) {
              if (!_selectingSuggestion) widget.onEdited?.call(value);
            },
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              prefixIcon: Icon(widget.icon,
                  color: widget.glassStyle ? colors.adminAccent : colors.text,
                  size: 18),
              labelText: widget.label,
              suffixIcon: widget.verified
                  ? Icon(Icons.verified, color: colors.success, size: 18)
                  : null,
              labelStyle: TextStyle(
                  color: colors.mutedText, fontWeight: FontWeight.w700),
              filled: !widget.glassStyle,
              fillColor: colors.field,
              border: OutlineInputBorder(
                borderSide: BorderSide.none,
                borderRadius:
                    BorderRadius.circular(widget.glassStyle ? 22 : 16),
              ),
              enabledBorder: widget.glassStyle
                  ? InputBorder.none
                  : OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16),
                    ),
              focusedBorder: widget.glassStyle
                  ? InputBorder.none
                  : OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16),
                    ),
            ),
          ),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._suggestions.map(
                (suggestion) => InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _resolvingSuggestion
                      ? null
                      : () => _selectSuggestion(suggestion),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: colors.field,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: suggestion.isPopularPlace
                            ? colors.adminAccent
                            : colors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          suggestion.isPopularPlace
                              ? Icons.star_rounded
                              : suggestion.isExactTypedAddress
                                  ? Icons.edit_location_alt_outlined
                                  : widget.pharmacyMode
                                      ? Icons.local_pharmacy
                                      : Icons.place_outlined,
                          color: colors.text,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                suggestion.displayAddress,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.text,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (suggestion.isPopularPlace ||
                                  suggestion.isExactTypedAddress)
                                Text(
                                  suggestion.isExactTypedAddress
                                      ? 'Use exact flat, house and street details'
                                      : _resolvingSuggestion
                                          ? 'Verifying free address data...'
                                          : 'Popular place${suggestion.category == null ? '' : ' • ${suggestion.category}'}',
                                  style: TextStyle(
                                    color: colors.mutedText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  widget.onEdited?.call(widget.controller.text);
                  setState(() => _suggestions = const []);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: colors.panel.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_location_alt_outlined,
                          color: colors.text, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Enter address manually',
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
        if (_loadingSuggestions || _resolvingSuggestion) ...[
          const SizedBox(height: 6),
          Text(
            _resolvingSuggestion
                ? 'Verifying selected place...'
                : 'Checking free UK address data...',
            style: TextStyle(
              color: colors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (_suggestionError != null) ...[
          const SizedBox(height: 6),
          Text(
            _suggestionError!,
            style: TextStyle(
              color: colors.warning,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ],
        if (widget.verified) ...[
          const SizedBox(height: 6),
          Container(
            padding: widget.glassStyle
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
                : EdgeInsets.zero,
            decoration: widget.glassStyle
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: colors.success.withValues(alpha: 0.10),
                    border: Border.all(
                        color: colors.success.withValues(alpha: 0.24)),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.glassStyle) ...[
                  Icon(Icons.verified_rounded, size: 14, color: colors.success),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.verifiedMessage,
                  style: TextStyle(
                    color: colors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PopularPlace {
  final String displayName;
  final List<String> searchAliases;
  final String formattedAddress;
  final double lat;
  final double lng;
  final String category;

  const _PopularPlace({
    required this.displayName,
    required this.searchAliases,
    required this.formattedAddress,
    required this.lat,
    required this.lng,
    required this.category,
  });

  bool matches(String normalizedInput) {
    return _normalizedSearchTerms.any(
      (term) =>
          term.contains(normalizedInput) || normalizedInput.contains(term),
    );
  }

  Iterable<String> get _normalizedSearchTerms sync* {
    yield _normalizePlaceQuery(displayName);
    yield _normalizePlaceQuery(formattedAddress);
    for (final alias in searchAliases) {
      yield _normalizePlaceQuery(alias);
    }
  }
}

const List<_PopularPlace> _circumPopularPlaces = [
  _PopularPlace(
    displayName: 'Heathrow Airport',
    searchAliases: ['heathrow', 'lhr', 'london heathrow'],
    formattedAddress: 'Heathrow Airport, Hounslow TW6, United Kingdom',
    lat: 51.4700,
    lng: -0.4543,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Heathrow Terminal 2 & 3',
    searchAliases: ['heathrow t2', 'heathrow t3', 'terminal 2', 'terminal 3'],
    formattedAddress:
        'Heathrow Terminal 2 & 3, Hounslow TW6 1EW, United Kingdom',
    lat: 51.4713,
    lng: -0.4524,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Heathrow Terminal 4',
    searchAliases: ['heathrow t4', 'terminal 4'],
    formattedAddress: 'Heathrow Terminal 4, Hounslow TW6 3XA, United Kingdom',
    lat: 51.4590,
    lng: -0.4464,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Heathrow Terminal 5',
    searchAliases: ['heathrow t5', 'terminal 5'],
    formattedAddress: 'Heathrow Terminal 5, Hounslow TW6 2GA, United Kingdom',
    lat: 51.4722,
    lng: -0.4870,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'King\'s Cross Station',
    searchAliases: ['kings cross', 'king cross', 'kings x', 'kx station'],
    formattedAddress:
        'King\'s Cross Station, Euston Road, London N1C 4TB, United Kingdom',
    lat: 51.5308,
    lng: -0.1238,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'St Pancras International',
    searchAliases: ['st pancras', 'saint pancras', 'st pancras station'],
    formattedAddress:
        'St Pancras International, Euston Road, London N1C 4QP, United Kingdom',
    lat: 51.5320,
    lng: -0.1252,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Euston Station',
    searchAliases: ['euston', 'london euston'],
    formattedAddress: 'Euston Station, London NW1 2RT, United Kingdom',
    lat: 51.5281,
    lng: -0.1339,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Paddington Station',
    searchAliases: ['paddington', 'london paddington'],
    formattedAddress:
        'Paddington Station, Praed Street, London W2 1HQ, United Kingdom',
    lat: 51.5154,
    lng: -0.1755,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Victoria Station',
    searchAliases: ['victoria', 'london victoria'],
    formattedAddress: 'Victoria Station, London SW1V 1JU, United Kingdom',
    lat: 51.4952,
    lng: -0.1441,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Waterloo Station',
    searchAliases: ['waterloo', 'london waterloo'],
    formattedAddress: 'Waterloo Station, London SE1 8SW, United Kingdom',
    lat: 51.5033,
    lng: -0.1147,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Liverpool Street Station',
    searchAliases: ['liverpool street', 'london liverpool street'],
    formattedAddress:
        'Liverpool Street Station, London EC2M 7QA, United Kingdom',
    lat: 51.5178,
    lng: -0.0817,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'London Bridge Station',
    searchAliases: ['london bridge'],
    formattedAddress: 'London Bridge Station, London SE1 9SP, United Kingdom',
    lat: 51.5050,
    lng: -0.0864,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Stratford Station',
    searchAliases: ['stratford', 'london stratford'],
    formattedAddress: 'Stratford Station, London E15 1AZ, United Kingdom',
    lat: 51.5413,
    lng: -0.0030,
    category: 'station',
  ),
  _PopularPlace(
    displayName: 'Gatwick Airport',
    searchAliases: ['gatwick', 'lgw', 'london gatwick'],
    formattedAddress: 'Gatwick Airport, Horley RH6 0NP, United Kingdom',
    lat: 51.1537,
    lng: -0.1821,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Luton Airport',
    searchAliases: ['luton', 'ltn', 'london luton'],
    formattedAddress: 'London Luton Airport, Luton LU2 9LY, United Kingdom',
    lat: 51.8747,
    lng: -0.3683,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Stansted Airport',
    searchAliases: ['stansted', 'stn', 'london stansted'],
    formattedAddress:
        'London Stansted Airport, Stansted CM24 1QW, United Kingdom',
    lat: 51.8860,
    lng: 0.2389,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'London City Airport',
    searchAliases: ['city airport', 'lcy'],
    formattedAddress:
        'London City Airport, Hartmann Road, London E16 2PX, United Kingdom',
    lat: 51.5053,
    lng: 0.0553,
    category: 'airport',
  ),
  _PopularPlace(
    displayName: 'Westfield Stratford City',
    searchAliases: ['westfield stratford', 'stratford westfield', 'westfield'],
    formattedAddress:
        'Westfield Stratford City, Montfichet Road, London E20 1EJ, United Kingdom',
    lat: 51.5432,
    lng: -0.0076,
    category: 'shopping centre',
  ),
  _PopularPlace(
    displayName: 'Westfield London White City',
    searchAliases: ['westfield white city', 'westfield london', 'westfield'],
    formattedAddress:
        'Westfield London, Ariel Way, London W12 7GF, United Kingdom',
    lat: 51.5074,
    lng: -0.2217,
    category: 'shopping centre',
  ),
  _PopularPlace(
    displayName: 'Canary Wharf',
    searchAliases: ['canary wharf'],
    formattedAddress: 'Canary Wharf, London E14, United Kingdom',
    lat: 51.5054,
    lng: -0.0235,
    category: 'business district',
  ),
  _PopularPlace(
    displayName: 'Oxford Street',
    searchAliases: ['oxford street'],
    formattedAddress: 'Oxford Street, London W1, United Kingdom',
    lat: 51.5154,
    lng: -0.1410,
    category: 'shopping area',
  ),
  _PopularPlace(
    displayName: 'Selfridges London',
    searchAliases: ['selfridges', 'selfridges london'],
    formattedAddress:
        'Selfridges, 400 Oxford Street, London W1A 1AB, United Kingdom',
    lat: 51.5145,
    lng: -0.1527,
    category: 'retail',
  ),
  _PopularPlace(
    displayName: 'Harrods',
    searchAliases: ['harrods', 'harrods london'],
    formattedAddress:
        'Harrods, 87-135 Brompton Road, London SW1X 7XL, United Kingdom',
    lat: 51.4994,
    lng: -0.1633,
    category: 'retail',
  ),
  _PopularPlace(
    displayName: 'IKEA Wembley',
    searchAliases: ['ikea wembley', 'ikea'],
    formattedAddress:
        'IKEA Wembley, 2 Drury Way, Wembley HA9 0TH, United Kingdom',
    lat: 51.5587,
    lng: -0.2600,
    category: 'retail',
  ),
  _PopularPlace(
    displayName: 'IKEA Greenwich',
    searchAliases: ['ikea greenwich', 'ikea'],
    formattedAddress:
        'IKEA Greenwich, 55-57 Bugsby\'s Way, London SE10 0QJ, United Kingdom',
    lat: 51.4907,
    lng: 0.0127,
    category: 'retail',
  ),
  _PopularPlace(
    displayName: 'IKEA Croydon',
    searchAliases: ['ikea croydon', 'ikea'],
    formattedAddress:
        'IKEA Croydon, Valley Park, Croydon CR0 4UZ, United Kingdom',
    lat: 51.3751,
    lng: -0.1220,
    category: 'retail',
  ),
  _PopularPlace(
    displayName: 'The O2 Arena',
    searchAliases: ['o2', 'o2 arena', 'the o2'],
    formattedAddress:
        'The O2 Arena, Peninsula Square, London SE10 0DX, United Kingdom',
    lat: 51.5030,
    lng: 0.0032,
    category: 'landmark',
  ),
  _PopularPlace(
    displayName: 'ExCeL London',
    searchAliases: ['excel', 'excel london', 'exhibition centre london'],
    formattedAddress:
        'ExCeL London, Royal Victoria Dock, London E16 1XL, United Kingdom',
    lat: 51.5085,
    lng: 0.0290,
    category: 'landmark',
  ),
  _PopularPlace(
    displayName: 'Wembley Stadium',
    searchAliases: ['wembley', 'wembley arena'],
    formattedAddress: 'Wembley Stadium, Wembley HA9 0WS, United Kingdom',
    lat: 51.5560,
    lng: -0.2796,
    category: 'stadium',
  ),
  _PopularPlace(
    displayName: 'Emirates Stadium',
    searchAliases: ['emirates stadium', 'arsenal stadium'],
    formattedAddress:
        'Emirates Stadium, Hornsey Road, London N7 7AJ, United Kingdom',
    lat: 51.5549,
    lng: -0.1084,
    category: 'stadium',
  ),
  _PopularPlace(
    displayName: 'Stamford Bridge',
    searchAliases: ['stamford bridge', 'chelsea stadium'],
    formattedAddress:
        'Stamford Bridge, Fulham Road, London SW6 1HS, United Kingdom',
    lat: 51.4816,
    lng: -0.1910,
    category: 'stadium',
  ),
  _PopularPlace(
    displayName: 'Tottenham Hotspur Stadium',
    searchAliases: ['tottenham stadium', 'spurs stadium'],
    formattedAddress:
        'Tottenham Hotspur Stadium, 782 High Road, London N17 0BX, United Kingdom',
    lat: 51.6043,
    lng: -0.0664,
    category: 'stadium',
  ),
  _PopularPlace(
    displayName: 'Guy\'s Hospital',
    searchAliases: ['guys hospital', 'guys nhs', 'london bridge hospital'],
    formattedAddress:
        'Guy\'s Hospital, Great Maze Pond, London SE1 9RT, United Kingdom',
    lat: 51.5031,
    lng: -0.0870,
    category: 'hospital',
  ),
  _PopularPlace(
    displayName: 'St Thomas\' Hospital',
    searchAliases: ['st thomas hospital', 'saint thomas nhs'],
    formattedAddress:
        'St Thomas\' Hospital, Westminster Bridge Road, London SE1 7EH, United Kingdom',
    lat: 51.4989,
    lng: -0.1187,
    category: 'hospital',
  ),
  _PopularPlace(
    displayName: 'University College Hospital',
    searchAliases: ['uch', 'uclh', 'university college hospital'],
    formattedAddress:
        'University College Hospital, 235 Euston Road, London NW1 2BU, United Kingdom',
    lat: 51.5247,
    lng: -0.1361,
    category: 'hospital',
  ),
  _PopularPlace(
    displayName: 'Boots Pharmacy, Oxford Street',
    searchAliases: ['boots oxford street', 'boots pharmacy oxford street'],
    formattedAddress:
        'Boots Pharmacy, 361 Oxford Street, London W1C 2JL, United Kingdom',
    lat: 51.5148,
    lng: -0.1488,
    category: 'pharmacy',
  ),
  _PopularPlace(
    displayName: 'King\'s College Hospital',
    searchAliases: ['kings college hospital', 'kch', 'denmark hill hospital'],
    formattedAddress:
        'King\'s College Hospital, Denmark Hill, London SE5 9RS, United Kingdom',
    lat: 51.4681,
    lng: -0.0937,
    category: 'nhs facility',
  ),
];

String _normalizePlaceQuery(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r"[\u2018\u2019']"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

bool _sameSuggestionText(String left, String right) {
  return _normalizePlaceQuery(left) == _normalizePlaceQuery(right);
}

const Map<String, (double, double)> _ukAddressSuggestionSeeds = {
  '10 Downing Street, Westminster, London SW1A 2AA, United Kingdom': (
    51.5034,
    -0.1276,
  ),
  '221B Baker Street, Marylebone, London NW1 6XE, United Kingdom': (
    51.5237,
    -0.1585,
  ),
  '1 Canada Square, Canary Wharf, London E14 5AB, United Kingdom': (
    51.5054,
    -0.0235,
  ),
  'The Shard, 32 London Bridge Street, London SE1 9SG, United Kingdom': (
    51.5045,
    -0.0865,
  ),
  'Westfield London, Ariel Way, London W12 7GF, United Kingdom': (
    51.5074,
    -0.2217,
  ),
  'Selfridges, 400 Oxford Street, London W1A 1AB, United Kingdom': (
    51.5145,
    -0.1527,
  ),
  'King\'s Cross Station, Euston Road, London N1C 4TB, United Kingdom': (
    51.5308,
    -0.1238,
  ),
  'Manchester Piccadilly Station, Manchester M1 2BN, United Kingdom': (
    53.4774,
    -2.2309,
  ),
  'Bullring, Birmingham B5 4BU, United Kingdom': (52.4776, -1.8936),
  'Cabot Circus, Bristol BS1 3BD, United Kingdom': (51.4581, -2.5837),
  'St James Quarter, Edinburgh EH1 3AD, United Kingdom': (55.9547, -3.1882),
  'Cardiff Central Station, Cardiff CF10 1EP, United Kingdom': (
    51.4755,
    -3.1780,
  ),
  'Leeds Station, New Station Street, Leeds LS1 4DY, United Kingdom': (
    53.7947,
    -1.5479,
  ),
  'Liverpool ONE, Liverpool L1 8JQ, United Kingdom': (53.4049, -2.9876),
  'Brighton Station, Queens Road, Brighton BN1 3XP, United Kingdom': (
    50.8290,
    -0.1413,
  ),
  'Oxford City Centre, Oxford OX1 1BX, United Kingdom': (51.7520, -1.2577),
};

const Map<String, (double, double)> _ukCityCoordinates = {
  'London': (51.5074, -0.1278),
  'Croydon': (51.3762, -0.0982),
  'Manchester': (53.4808, -2.2426),
  'Birmingham': (52.4862, -1.8904),
  'Bristol': (51.4545, -2.5879),
  'Edinburgh': (55.9533, -3.1883),
  'Cardiff': (51.4816, -3.1791),
  'Leeds': (53.8008, -1.5491),
  'Liverpool': (53.4084, -2.9916),
  'Brighton': (50.8225, -0.1372),
  'Oxford': (51.7520, -1.2577),
};

const Map<String, (double, double)> _ukPostcodeCoordinates = {
  'SE1': (51.5033, -0.0890),
  'SE2': (51.4882, 0.1213),
  'SE3': (51.4685, 0.0196),
  'SE4': (51.4612, -0.0379),
  'SE5': (51.4736, -0.0920),
  'SE6': (51.4339, -0.0166),
  'SE7': (51.4869, 0.0312),
  'SE8': (51.4825, -0.0279),
  'SE9': (51.4504, 0.0513),
  'SE10': (51.4816, -0.0011),
  'SE11': (51.4901, -0.1101),
  'SE12': (51.4452, 0.0138),
  'SE13': (51.4589, -0.0117),
  'SE14': (51.4757, -0.0406),
  'SE15': (51.4735, -0.0671),
  'SE16': (51.4979, -0.0535),
  'SE17': (51.4880, -0.0923),
  'SE18': (51.4896, 0.0708),
  'SE19': (51.4195, -0.0868),
  'SE20': (51.4125, -0.0551),
  'SE21': (51.4402, -0.0886),
  'SE22': (51.4530, -0.0720),
  'SE23': (51.4416, -0.0497),
  'SE24': (51.4538, -0.1012),
  'SE25': (51.3995, -0.0751),
  'SE26': (51.4267, -0.0546),
  'SE27': (51.4306, -0.1033),
  'SE28': (51.5029, 0.1042),
  'CR0': (51.3762, -0.0982),
  'CR2': (51.3452, -0.0920),
  'CR3': (51.2853, -0.0801),
  'CR4': (51.4035, -0.1604),
  'CR5': (51.3093, -0.1392),
  'CR6': (51.3095, -0.0579),
  'CR7': (51.3987, -0.1071),
  'CR8': (51.3373, -0.1151),
  'E': (51.5326, 0.0553),
  'EC': (51.5155, -0.0922),
  'N': (51.5680, -0.1080),
  'NW': (51.5480, -0.1980),
  'SW': (51.4450, -0.1700),
  'W': (51.5120, -0.2200),
  'WC': (51.5190, -0.1200),
  'BR': (51.4060, 0.0150),
  'DA': (51.4470, 0.2190),
  'EN': (51.6520, -0.0810),
  'HA': (51.5810, -0.3370),
  'IG': (51.5590, 0.0750),
  'KT': (51.3920, -0.3000),
  'RM': (51.5600, 0.1830),
  'SM': (51.3650, -0.1950),
  'TW': (51.4490, -0.4100),
  'UB': (51.5200, -0.4100),
  'WD': (51.6600, -0.3900),
  'M': (53.4808, -2.2426),
  'B': (52.4862, -1.8904),
  'BS': (51.4545, -2.5879),
  'EH': (55.9533, -3.1883),
  'CF': (51.4816, -3.1791),
  'LS': (53.8008, -1.5491),
  'L': (53.4084, -2.9916),
  'BN': (50.8225, -0.1372),
  'OX': (51.7520, -1.2577),
};

class _RouteRow extends StatelessWidget {
  final _CircumColors colors;
  final String from;
  final String to;

  const _RouteRow({required this.colors, required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RoutePoint(colors: colors, label: 'Pickup', value: from, first: true),
        Padding(
          padding: const EdgeInsets.only(left: 11),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(width: 2, height: 24, color: colors.border),
          ),
        ),
        _RoutePoint(colors: colors, label: 'Drop-off', value: to, first: false),
      ],
    );
  }
}

class _RoutePoint extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;
  final bool first;

  const _RoutePoint({
    required this.colors,
    required this.label,
    required this.value,
    required this.first,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          first ? Icons.radio_button_checked : Icons.location_on,
          color: first ? const Color(0xff2563eb) : const Color(0xff16a34a),
          size: 24,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PriceLine extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;
  final bool strong;

  const _PriceLine({
    required this.colors,
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong ? colors.text : colors.mutedText,
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
                fontSize: strong ? 17 : 14,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.text,
              fontWeight: FontWeight.w900,
              fontSize: strong ? 20 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

enum _PlatformPaymentKind { applePay, googlePay, savedCards, addCard, card }

class _PlatformPaymentOption {
  final _PlatformPaymentKind kind;
  final String label;
  final IconData icon;

  const _PlatformPaymentOption(this.kind, this.label, this.icon);
}

class _PlatformPaymentProfile {
  final List<_PlatformPaymentOption> options;
  final String primaryLabel;

  const _PlatformPaymentProfile({
    required this.options,
    required this.primaryLabel,
  });

  factory _PlatformPaymentProfile.detect() {
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    final isApple = userAgent.contains('iphone') ||
        userAgent.contains('ipad') ||
        userAgent.contains('ipod') ||
        (userAgent.contains('macintosh') && userAgent.contains('mobile'));
    final isAndroid = userAgent.contains('android');
    final applePayAvailable = isApple;
    final googlePayAvailable = isAndroid &&
        (userAgent.contains('chrome') ||
            userAgent.contains('crios') ||
            userAgent.contains('wv'));

    if (isApple) {
      return _PlatformPaymentProfile(
        primaryLabel: applePayAvailable ? 'Apple Pay' : 'Saved cards',
        options: [
          if (applePayAvailable)
            const _PlatformPaymentOption(
              _PlatformPaymentKind.applePay,
              'Apple Pay',
              Icons.apple,
            ),
          const _PlatformPaymentOption(
            _PlatformPaymentKind.savedCards,
            'Saved cards',
            Icons.credit_card,
          ),
          const _PlatformPaymentOption(
            _PlatformPaymentKind.addCard,
            'Add card',
            Icons.add_card_outlined,
          ),
        ],
      );
    }
    if (isAndroid) {
      return _PlatformPaymentProfile(
        primaryLabel: googlePayAvailable ? 'Google Pay' : 'Saved cards',
        options: [
          if (googlePayAvailable)
            const _PlatformPaymentOption(
              _PlatformPaymentKind.googlePay,
              'Google Pay',
              Icons.g_mobiledata,
            ),
          const _PlatformPaymentOption(
            _PlatformPaymentKind.savedCards,
            'Saved cards',
            Icons.credit_card,
          ),
          const _PlatformPaymentOption(
            _PlatformPaymentKind.addCard,
            'Add card',
            Icons.add_card_outlined,
          ),
        ],
      );
    }
    return const _PlatformPaymentProfile(
      primaryLabel: 'Card payment',
      options: [
        _PlatformPaymentOption(
          _PlatformPaymentKind.savedCards,
          'Saved cards',
          Icons.credit_card,
        ),
        _PlatformPaymentOption(
          _PlatformPaymentKind.card,
          'Card payment',
          Icons.payment_outlined,
        ),
      ],
    );
  }
}

class _PlatformPaymentMethods extends StatelessWidget {
  final _CircumColors colors;
  final _PlatformPaymentProfile profile;

  const _PlatformPaymentMethods({
    required this.colors,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: profile.options
          .map(
            (option) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withValues(alpha: 0.07),
                border: Border.all(
                  color: colors.adminAccent.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(option.icon, color: colors.text, size: 18),
                  const SizedBox(width: 7),
                  Text(
                    option.label,
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _CircumPaymentSummary extends StatelessWidget {
  final _CircumColors colors;
  final String serviceName;
  final String totalLabel;
  final double total;
  final double rothAvailable;
  final String? ctaLabel;

  const _CircumPaymentSummary({
    required this.colors,
    required this.serviceName,
    required this.totalLabel,
    required this.total,
    required this.rothAvailable,
    this.ctaLabel,
  });

  @override
  Widget build(BuildContext context) {
    final available = math.max(0, rothAvailable);
    final applied = math.min(total, available);
    final remaining = math.max(0, total - applied);
    final paymentProfile = _PlatformPaymentProfile.detect();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xff0f4cff).withValues(alpha: 0.28),
            const Color(0xff111827).withValues(alpha: 0.86),
            const Color(0xff7c3aed).withValues(alpha: 0.24),
          ],
        ),
        border: Border.all(
          color: const Color(0xff67e8f9).withValues(alpha: 0.30),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff2563eb).withValues(alpha: 0.24),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: const Color(0xffa855f7).withValues(alpha: 0.12),
            blurRadius: 46,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xff67e8f9), Color(0xff8b5cf6)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xff67e8f9).withValues(alpha: 0.28),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  serviceName,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PriceLine(
            colors: colors,
            label: totalLabel,
            value: '£${total.toStringAsFixed(2)}',
            strong: true,
          ),
          _PriceLine(
            colors: colors,
            label: 'Roth available',
            value: '£${available.toStringAsFixed(2)}',
          ),
          _PriceLine(
            colors: colors,
            label: 'Roth Applied',
            value: '£${applied.toStringAsFixed(2)}',
            strong: applied > 0,
          ),
          _PriceLine(
            colors: colors,
            label: 'Card Remaining',
            value: '£${remaining.toStringAsFixed(2)}',
            strong: true,
          ),
          const SizedBox(height: 10),
          Text(
            'Card Remaining',
            style: TextStyle(
              color: colors.mutedText,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          Text(
            '£${remaining.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            remaining <= 0
                ? 'Payment method: Roth only. No card payment required.'
                : applied > 0
                    ? 'Payment method: Roth first, then ${paymentProfile.primaryLabel} for the remaining balance.'
                    : 'Payment method: ${paymentProfile.primaryLabel}.',
            style: TextStyle(
              color: colors.mutedText,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (remaining > 0) ...[
            const SizedBox(height: 10),
            _PlatformPaymentMethods(
              colors: colors,
              profile: paymentProfile,
            ),
          ],
          if (ctaLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              ctaLabel!,
              style: TextStyle(
                color: colors.text,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  final _CircumColors colors;
  final Widget child;

  const _GlassPanel({super.key, required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
            sigmaX: colors.dark ? 14 : 8, sigmaY: colors.dark ? 14 : 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.panel.withOpacity(colors.dark ? 0.82 : 0.95),
                colors.adminAccent.withOpacity(colors.dark ? 0.13 : 0.07),
                colors.panel.withOpacity(colors.dark ? 0.74 : 0.93),
              ],
            ),
            borderRadius: radius,
            border: Border.all(
              color: Color.alphaBlend(
                colors.adminAccent.withOpacity(colors.dark ? 0.18 : 0.12),
                Colors.white.withOpacity(colors.dark ? 0.08 : 0.18),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(colors.dark ? 0.24 : 0.06),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: colors.adminGlow.withOpacity(colors.dark ? 0.14 : 0.06),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final _CircumColors colors;
  final IconData icon;
  final Color tint;
  final String title;
  final String body;

  const _FeatureCard({
    required this.colors,
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: const Color(0xff2563eb)),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: TextStyle(
              color: colors.text,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              color: colors.mutedText,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final _CircumColors colors;
  final String label;
  final String value;

  const _MetricPill({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: colors.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoTile extends StatelessWidget {
  final _CircumColors colors;

  const _LogoTile({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.text,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.all_inclusive, color: colors.inverseText),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool dark;
  final VoidCallback onPressed;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.dark,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: dark ? Colors.black : const Color(0xfff3f4f6),
        foregroundColor: dark ? Colors.white : Colors.black,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _VanguardLandingBand extends StatelessWidget {
  final _CircumColors colors;

  const _VanguardLandingBand({required this.colors});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xff3b82f6);
    const features = [
      (Icons.verified_user_outlined, 'Trusted Rider Prioritisation'),
      (Icons.route_outlined, 'Enhanced Custody Tracking'),
      (Icons.support_agent, 'Priority Support'),
      (Icons.fact_check_outlined, 'Priority Dispute Review'),
    ];
    return Container(
      width: double.infinity,
      color: const Color(0xff07090f),
      padding: const EdgeInsets.fromLTRB(22, 54, 22, 54),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            children: [
              const Icon(Icons.shield_outlined, color: blue, size: 38),
              const SizedBox(height: 16),
              Text(
                'Trust matters more than speed.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white,
                  fontSize: 38,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Add Vanguard for £1.99 and receive enhanced custody tracking, trusted rider prioritisation, priority support, and better handling for important deliveries.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.74),
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: features
                    .map((feature) => Container(
                          width: 220,
                          constraints: const BoxConstraints(minHeight: 92),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.11)),
                          ),
                          child: Row(
                            children: [
                              Icon(feature.$1, color: blue, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  feature.$2,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.base.resolve('/vanguard'),
                  webOnlyWindowName: '_self',
                ),
                icon: const Icon(Icons.arrow_forward, size: 17),
                label: const Text('Learn more'),
                style: TextButton.styleFrom(foregroundColor: blue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessLandingBand extends StatelessWidget {
  final _CircumColors colors;
  final VoidCallback onBusinessLogin;
  final VoidCallback onCreateBusiness;

  const _BusinessLandingBand({
    required this.colors,
    required this.onBusinessLogin,
    required this.onCreateBusiness,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 920;
    const uses = [
      (
        Icons.groups_2_outlined,
        'Team deliveries',
        'Book, track, and manage deliveries across departments.'
      ),
      (
        Icons.receipt_long_outlined,
        'Invoicing',
        'Centralised billing, outstanding invoices, and account credit.'
      ),
      (
        Icons.health_and_safety_outlined,
        'Health+',
        'Manage prescription and medical deliveries for staff or clients.'
      ),
      (
        Icons.card_giftcard_outlined,
        'Gifts',
        'Send approved corporate gifts through Gifts by Circum.'
      ),
      (
        Icons.shield_outlined,
        'Vanguard',
        'Add higher-trust delivery assurance for sensitive items.'
      ),
      (
        Icons.dashboard_customize_outlined,
        'Dashboard',
        'Access the Business Account overview and ecosystem hub.'
      ),
    ];
    return Container(
      width: double.infinity,
      color: const Color(0xff07090f),
      padding: const EdgeInsets.fromLTRB(22, 64, 22, 68),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            children: [
              Flex(
                direction: narrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: narrow ? 0 : 9,
                    child: Column(
                      crossAxisAlignment: narrow
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      children: [
                        const _BusinessEyebrow('Business Accounts'),
                        const SizedBox(height: 12),
                        Text(
                          'Built for companies that move things.',
                          textAlign: narrow ? TextAlign.center : TextAlign.left,
                          style: GoogleFonts.dmSerifDisplay(
                            color: Colors.white,
                            fontSize: narrow ? 42 : 58,
                            height: 1.02,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Manage deliveries, invoices, team access, Health+, Gifts, and Vanguard from one business account. Circum gives companies a single command centre for everything they send.',
                          textAlign: narrow ? TextAlign.center : TextAlign.left,
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.76),
                            fontSize: 17,
                            height: 1.55,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: narrow
                              ? WrapAlignment.center
                              : WrapAlignment.start,
                          children: [
                            FilledButton.icon(
                              onPressed: onBusinessLogin,
                              icon: const Icon(Icons.login_rounded),
                              label: const Text('Business login'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xff07090f),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 17),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: onCreateBusiness,
                              icon: const Icon(Icons.add_business_rounded),
                              label: const Text('Create business account'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.24),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 17),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: narrow ? 0 : 34, height: narrow ? 28 : 0),
                  Expanded(
                    flex: narrow ? 0 : 8,
                    child: _BusinessLandingPreview(onOpen: onBusinessLogin),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth < 720
                      ? 1
                      : constraints.maxWidth < 1040
                          ? 2
                          : 3;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: cols,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: cols == 1 ? 3.15 : 2.2,
                    children: uses
                        .map(
                          (item) => _BusinessMiniCard(
                            icon: item.$1,
                            title: item.$2,
                            body: item.$3,
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessLandingPreview extends StatelessWidget {
  final VoidCallback onOpen;

  const _BusinessLandingPreview({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final rows = [
      (Icons.local_shipping_outlined, 'Deliveries', 'Live jobs and routes'),
      (Icons.receipt_long_outlined, 'Invoicing', 'Credit and billing'),
      (Icons.groups_2_outlined, 'Team access', 'Owners, admins, members'),
      (Icons.shield_outlined, 'Vanguard', 'Higher-trust handling'),
    ];
    return _BusinessGlass(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _BusinessBadge('BUSINESS PAGE'),
              const Spacer(),
              IconButton(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new_rounded),
                color: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Command centre lives on its own page.',
            style: GoogleFonts.dmSerifDisplay(
              color: Colors.white,
              fontSize: 34,
              height: 1.04,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Open Business from the header to access the full dashboard, team controls, invoices, activity and ecosystem hub.',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(row.$1, color: const Color(0xff3b82f6), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.$2,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            row.$3,
                            style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.58),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white54, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.business_center_rounded),
              label: const Text('Open Business page'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xff07090f),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessCommandPage extends StatefulWidget {
  final _CircumColors colors;
  final VoidCallback onHome;
  final VoidCallback onAccess;

  const _BusinessCommandPage({
    super.key,
    required this.colors,
    required this.onHome,
    required this.onAccess,
  });

  @override
  State<_BusinessCommandPage> createState() => _BusinessCommandPageState();
}

enum _BusinessPortalTab {
  overview,
  invoicing,
  team,
  deliveries,
  healthPlus,
  gifts,
  vanguard,
  analytics,
  settings,
}

class _BusinessCommandPageState extends State<_BusinessCommandPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _businessName = TextEditingController();
  final _contactName = TextEditingController();
  final _phone = TextEditingController();
  final _businessAddress = TextEditingController();
  final _companyNumber = TextEditingController();
  final _billingEmail = TextEditingController();
  final _defaultPickupAddress = TextEditingController();
  final _inviteEmail = TextEditingController();
  final _inviteName = TextEditingController();
  final _invoiceSearch = TextEditingController();
  var _tab = _BusinessPortalTab.overview;
  var _signupMode = false;
  var _busy = false;
  var _message = '';
  var _selectedBusinessId = '';
  var _inviteRole = 'operations';
  var _returnPaymentStatus = '';
  var _returnInvoiceId = '';
  Map<String, dynamic>? _returnInvoice;
  final Stream<User?> _authStream = FirebaseAuth.instance.authStateChanges();
  Stream<List<Map<String, dynamic>>>? _cachedBusinessAccountsStream;
  String? _cachedBusinessAccountsUserId;
  Stream<List<Map<String, dynamic>>>? _cachedBusinessDeliveriesStream;
  String? _cachedBusinessDeliveriesId;

  @override
  void initState() {
    super.initState();
    _captureBusinessPaymentReturn();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _businessName.dispose();
    _contactName.dispose();
    _phone.dispose();
    _businessAddress.dispose();
    _companyNumber.dispose();
    _billingEmail.dispose();
    _defaultPickupAddress.dispose();
    _inviteEmail.dispose();
    _inviteName.dispose();
    _invoiceSearch.dispose();
    super.dispose();
  }

  void _captureBusinessPaymentReturn() {
    final params = Uri.base.queryParameters;
    final invoiceId = '${params['invoiceId'] ?? ''}'.trim();
    var status = '${params['paymentStatus'] ?? ''}'.trim();
    final legacyStatus = '${params['invoice_payment'] ?? ''}'.trim();
    if (status.isEmpty && legacyStatus == 'success') {
      status = 'payment-success';
    } else if (status.isEmpty && legacyStatus == 'cancelled') {
      status = 'payment-cancelled';
    }
    if (invoiceId.isEmpty && status.isEmpty) return;
    _tab = _BusinessPortalTab.invoicing;
    _returnInvoiceId = invoiceId;
    _returnPaymentStatus = status;
    if (invoiceId.isNotEmpty) {
      unawaited(_hydrateReturnedInvoice(invoiceId));
    }
  }

  Future<void> _hydrateReturnedInvoice(String invoiceId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('businessInvoices')
          .doc(invoiceId)
          .get();
      if (!mounted || !snap.exists) return;
      setState(() => _returnInvoice = {'id': snap.id, ...?snap.data()});
    } catch (error) {
      debugPrint('business invoice return recovery failed: $error');
    }
  }

  Future<void> _signIn() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _message = 'Add your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      if (_signupMode) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _message = error.message ?? 'Authentication failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _message = 'Enter your email first.');
      return;
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    if (mounted) setState(() => _message = 'Password reset email sent.');
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      setState(() {
        _selectedBusinessId = '';
        _tab = _BusinessPortalTab.overview;
        _cachedBusinessAccountsStream = null;
        _cachedBusinessAccountsUserId = null;
        _cachedBusinessDeliveriesStream = null;
        _cachedBusinessDeliveriesId = null;
      });
    }
  }

  Stream<List<Map<String, dynamic>>> _businessAccounts(User user) {
    if (_cachedBusinessAccountsUserId == user.uid &&
        _cachedBusinessAccountsStream != null) {
      return _cachedBusinessAccountsStream!;
    }
    final email = (user.email ?? '').trim().toLowerCase();
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    final records = <String, Map<String, dynamic>>{};

    void emit() {
      if (controller.isClosed) return;
      controller.add(records.values.toList(growable: false)
        ..sort((a, b) => '${a['businessName'] ?? ''}'
            .compareTo('${b['businessName'] ?? ''}')));
    }

    void addSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
      for (final doc in snapshot.docs) {
        records[doc.id] = <String, dynamic>{'id': doc.id, ...doc.data()};
      }
      emit();
    }

    final db = FirebaseFirestore.instance.collection('businessAccounts');
    final subscriptions = <StreamSubscription>[
      db
          .where('createdByUserId', isEqualTo: user.uid)
          .limit(20)
          .snapshots()
          .listen(addSnapshot, onError: (_) => emit()),
      db
          .where('teamMemberIds',
              arrayContainsAny: [user.uid, if (email.isNotEmpty) email])
          .limit(20)
          .snapshots()
          .listen(addSnapshot, onError: (_) => emit()),
    ];
    controller.onCancel = () {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    };
    _cachedBusinessAccountsUserId = user.uid;
    _cachedBusinessAccountsStream = controller.stream;
    return _cachedBusinessAccountsStream!;
  }

  Stream<List<Map<String, dynamic>>> _businessDeliveries(String businessId) {
    if (businessId.isEmpty) return const Stream.empty();
    if (_cachedBusinessDeliveriesId == businessId &&
        _cachedBusinessDeliveriesStream != null) {
      return _cachedBusinessDeliveriesStream!;
    }
    _cachedBusinessDeliveriesId = businessId;
    _cachedBusinessDeliveriesStream = FirebaseFirestore.instance
        .collection('deliveryRequests')
        .where('businessId', isEqualTo: businessId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
            .toList(growable: false)
          ..sort((a, b) => _businessDate(b).compareTo(_businessDate(a))));
    return _cachedBusinessDeliveriesStream!;
  }

  Future<void> _createBusiness(User user) async {
    final name = _businessName.text.trim();
    final contactName = _contactName.text.trim();
    final email = (user.email ?? _email.text).trim().toLowerCase();
    if (name.isEmpty || contactName.isEmpty || email.isEmpty) {
      setState(() =>
          _message = 'Business name, contact name and email are required.');
      return;
    }
    final doc = FirebaseFirestore.instance.collection('businessAccounts').doc();
    final member = {
      'userId': user.uid,
      'email': email,
      'name': contactName,
      'role': 'owner',
      'joinedAt': Timestamp.now(),
      'status': 'active',
    };
    await doc.set({
      'businessId': doc.id,
      'businessName': name,
      'contactName': contactName,
      'contactEmail': email,
      'phone': _phone.text.trim(),
      'businessAddress': _businessAddress.text.trim(),
      'companyNumber': _companyNumber.text.trim(),
      'billingEmail': _billingEmail.text.trim().isEmpty
          ? email
          : _billingEmail.text.trim().toLowerCase(),
      'defaultPickupAddresses': [
        if (_defaultPickupAddress.text.trim().isNotEmpty)
          _defaultPickupAddress.text.trim()
        else if (_businessAddress.text.trim().isNotEmpty)
          _businessAddress.text.trim(),
      ],
      'createdByUserId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'status': 'pending',
      'teamMemberIds': [user.uid],
      'managerIds': [user.uid],
      'teamMembers': [member],
      'monthlySpendLimit': null,
      'notes': '',
    });
    _businessName.clear();
    _contactName.clear();
    _phone.clear();
    _businessAddress.clear();
    _companyNumber.clear();
    _billingEmail.clear();
    _defaultPickupAddress.clear();
    if (mounted) {
      setState(() {
        _selectedBusinessId = doc.id;
        _tab = _BusinessPortalTab.overview;
        _signupMode = false;
        _message =
            'Business account created. Circum admin approval unlocks booking.';
      });
    }
  }

  Future<void> _saveProfile(Map<String, dynamic> account) async {
    final id = '${account['id'] ?? account['businessId'] ?? ''}';
    if (id.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('businessAccounts')
        .doc(id)
        .set({
      'businessName': _businessName.text.trim(),
      'contactName': _contactName.text.trim(),
      'phone': _phone.text.trim(),
      'businessAddress': _businessAddress.text.trim(),
      'companyNumber': _companyNumber.text.trim(),
      'billingEmail': _billingEmail.text.trim().toLowerCase(),
      'defaultPickupAddresses': [
        if (_defaultPickupAddress.text.trim().isNotEmpty)
          _defaultPickupAddress.text.trim(),
      ],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) setState(() => _message = 'Business profile saved.');
  }

  Future<void> _addBusinessMoment(Map<String, dynamic> account) async {
    final id = '${account['id'] ?? account['businessId'] ?? ''}';
    if (id.isEmpty) return;
    final moment = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _BusinessMomentDialog(),
    );
    if (moment == null) return;
    await FirebaseFirestore.instance
        .collection('businessAccounts')
        .doc(id)
        .set({
      'irisMoments': FieldValue.arrayUnion([moment]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) {
      setState(() => _message = 'IRIS Moment added.');
    }
  }

  Future<void> _inviteMember(Map<String, dynamic> account) async {
    final id = '${account['id'] ?? account['businessId'] ?? ''}';
    final email = _inviteEmail.text.trim().toLowerCase();
    if (id.isEmpty || email.isEmpty) return;
    final member = {
      'userId': email,
      'email': email,
      'name': _inviteName.text.trim(),
      'role': _inviteRole,
      'joinedAt': Timestamp.now(),
      'status': 'invited',
    };
    await FirebaseFirestore.instance
        .collection('businessAccounts')
        .doc(id)
        .set({
      'teamMemberIds': FieldValue.arrayUnion([email]),
      if (_inviteRole == 'owner' || _inviteRole == 'admin')
        'managerIds': FieldValue.arrayUnion([email]),
      'teamMembers': FieldValue.arrayUnion([member]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _inviteEmail.clear();
    _inviteName.clear();
    if (mounted) setState(() => _message = 'Team invite saved.');
  }

  Future<void> _updateMember(
    Map<String, dynamic> account,
    Map<String, dynamic> member, {
    String? role,
    bool remove = false,
    bool cancelInvite = false,
    bool resendInvite = false,
  }) async {
    final id = '${account['id'] ?? account['businessId'] ?? ''}';
    final memberId = '${member['userId'] ?? member['email'] ?? ''}';
    if (id.isEmpty || memberId.isEmpty) return;
    final members = ((account['teamMembers'] as List?) ?? const [])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((item) => '${item['userId'] ?? item['email'] ?? ''}' != memberId)
        .toList(growable: true);
    if (!remove && !cancelInvite) {
      members.add({
        ...member,
        if (role != null) 'role': role,
        if (resendInvite) 'resentAt': Timestamp.now(),
        if (resendInvite) 'status': 'invited',
      });
    }
    final memberIds = members
        .map((item) => '${item['userId'] ?? item['email'] ?? ''}')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final managerIds = members
        .where((item) => item['role'] == 'owner' || item['role'] == 'admin')
        .map((item) => '${item['userId'] ?? item['email'] ?? ''}')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    await FirebaseFirestore.instance
        .collection('businessAccounts')
        .doc(id)
        .set({
      'teamMembers': members,
      'teamMemberIds': memberIds,
      'managerIds': managerIds,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _requestBusinessRothPurchase(
    Map<String, dynamic> account,
    User user,
  ) async {
    if (_busy) return;
    final businessId = '${account['id'] ?? account['businessId'] ?? ''}';
    if (businessId.isEmpty) return;
    final request = await showDialog<_BusinessRothPurchaseRequest>(
      context: context,
      builder: (context) => const _BusinessRothPurchaseDialog(),
    );
    if (request == null || request.amount <= 0 || !request.amount.isFinite) {
      return;
    }
    if (request.method == 'card') {
      setState(() {
        _busy = true;
        _message = 'Starting secure checkout...';
      });
      try {
        final result =
            await FirebaseFunctions.instanceFor(region: 'us-central1')
                .httpsCallable('createBusinessRothCheckout')
                .call({
          'businessId': businessId,
          'amount': request.amount,
          'returnUrl':
              '${html.window.location.origin}/?app=business&section=invoicing',
        });
        final checkoutUrl = '${result.data['checkoutUrl'] ?? ''}';
        if (checkoutUrl.isEmpty) {
          throw StateError('Missing checkout URL');
        }
        if (mounted) {
          setState(() => _message =
              'Payment received. Roth will appear once confirmation completes.');
        }
        html.window.location.assign(checkoutUrl);
      } catch (error) {
        debugPrint('createBusinessRothCheckout failed: $error');
        if (mounted) {
          setState(() {
            _busy = false;
            _message =
                'Stripe checkout could not be started. Please try again.';
          });
        }
      }
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Submitting payment request...';
    });
    final purchaseRef =
        FirebaseFirestore.instance.collection('businessRothPurchases').doc();
    final purchase = {
      'purchaseId': purchaseRef.id,
      'businessId': businessId,
      'businessName': account['businessName'],
      'amountGbp': request.amount,
      'amountRoth': request.amount,
      'rothAmount': request.amount,
      'status': 'pending',
      'paymentMethod': 'manual',
      'paymentProvider': 'manual',
      'createdAt': FieldValue.serverTimestamp(),
      'paidAt': null,
      'createdByBusinessMemberId': user.uid,
      'createdByUserId': user.uid,
      'createdByBusinessMemberEmail': user.email,
      'resultingBalance': null,
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.set(purchaseRef, purchase);
    batch.set(
        FirebaseFirestore.instance
            .collection('businessAccounts')
            .doc(businessId),
        {
          'recentBusinessRothPurchases': FieldValue.arrayUnion([
            {
              'purchaseId': purchaseRef.id,
              'amountGbp': request.amount,
              'rothAmount': request.amount,
              'status': 'pending',
              'paymentProvider': 'manual',
              'createdAt': Timestamp.now(),
            }
          ]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    try {
      await batch.commit();
      if (mounted) {
        setState(() {
          _busy = false;
          _message =
              'Roth top-up request created. Circum will confirm payment before crediting Roth.';
        });
      }
    } catch (error) {
      debugPrint('business manual Roth request failed: $error');
      if (mounted) {
        setState(() {
          _busy = false;
          _message =
              'Manual payment request could not be submitted. Please try again.';
        });
      }
    }
  }

  Future<void> _payBusinessInvoice(
    Map<String, dynamic> account,
    Map<String, dynamic> invoice,
    String method,
  ) async {
    if (_busy) return;
    final businessId = '${account['id'] ?? account['businessId'] ?? ''}';
    final invoiceId = '${invoice['invoiceId'] ?? invoice['id'] ?? ''}';
    final balance = _num(invoice['balanceDue'] ?? invoice['total']);
    if (businessId.isEmpty || invoiceId.isEmpty || balance <= 0) return;
    final rothBalance =
        _num(account['rothBalance'] ?? account['businessRothBalance']);
    var paymentAmount = balance;
    var rothAmount = 0.0;
    if (method == 'roth') {
      paymentAmount = math.min(balance, rothBalance);
      rothAmount = paymentAmount;
      if (rothAmount <= 0) return;
    } else if (method == 'part') {
      final result = await showDialog<_BusinessInvoicePartPaymentRequest>(
        context: context,
        builder: (context) => _BusinessPartPaymentDialog(
          maxAmount: balance,
          rothBalance: rothBalance,
        ),
      );
      if (result == null || result.amount <= 0) return;
      paymentAmount = result.amount;
      if (result.method == 'roth') {
        rothAmount = result.amount;
      }
    }
    setState(() {
      _busy = true;
      _message = method == 'roth'
          ? 'Paying invoice with Business Roth...'
          : 'Starting secure checkout...';
    });
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createBusinessInvoiceCheckout')
          .call({
        'businessId': businessId,
        'invoiceId': invoiceId,
        'paymentAmount': paymentAmount,
        'rothAmount': rothAmount,
        'returnUrl':
            '${html.window.location.origin}/?app=business&section=invoicing&invoiceId=$invoiceId',
      });
      if (result.data['paid'] == true) {
        if (mounted) {
          setState(() {
            _busy = false;
            _message = paymentAmount >= balance
                ? 'Invoice paid using Roth.'
                : 'Part payment made. Your remaining balance has been updated.';
          });
        }
        return;
      }
      final checkoutUrl = '${result.data['checkoutUrl'] ?? ''}';
      if (checkoutUrl.isEmpty) throw StateError('Missing checkout URL');
      if (mounted) {
        setState(() => _message =
            'Invoice payment started. Waiting for payment confirmation.');
      }
      html.window.location.assign(checkoutUrl);
    } catch (error) {
      debugPrint('createBusinessInvoiceCheckout failed: $error');
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Stripe checkout could not be started. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, auth) {
        final user = auth.data;
        if (auth.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xff07090f),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (user == null) {
          return _BusinessAuthGate(
            signupMode: _signupMode,
            busy: _busy,
            message: _message,
            email: _email,
            password: _password,
            onToggleMode: () => setState(() => _signupMode = !_signupMode),
            onSubmit: _signIn,
            onResetPassword: _resetPassword,
            onHome: widget.onHome,
          );
        }
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _businessAccounts(user),
          builder: (context, accountsSnapshot) {
            if (!accountsSnapshot.hasData &&
                accountsSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xff07090f),
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final accounts =
                accountsSnapshot.data ?? const <Map<String, dynamic>>[];
            final selected = _selectedAccount(accounts);
            if (selected == null) {
              return _BusinessOnboardingPage(
                message: _message,
                businessName: _businessName,
                contactName: _contactName,
                phone: _phone,
                businessAddress: _businessAddress,
                companyNumber: _companyNumber,
                billingEmail: _billingEmail,
                defaultPickupAddress: _defaultPickupAddress,
                onCreate: () => _createBusiness(user),
                onSignOut: _signOut,
              );
            }
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _businessDeliveries(
                  '${selected['id'] ?? selected['businessId'] ?? ''}'),
              builder: (context, deliveriesSnapshot) {
                final deliveries =
                    deliveriesSnapshot.data ?? const <Map<String, dynamic>>[];
                return _BusinessPortalScaffold(
                  user: user,
                  accounts: accounts,
                  selectedAccount: selected,
                  selectedTab: _tab,
                  deliveries: deliveries,
                  message: _message,
                  businessName: _businessName,
                  contactName: _contactName,
                  phone: _phone,
                  businessAddress: _businessAddress,
                  companyNumber: _companyNumber,
                  billingEmail: _billingEmail,
                  defaultPickupAddress: _defaultPickupAddress,
                  inviteEmail: _inviteEmail,
                  inviteName: _inviteName,
                  inviteRole: _inviteRole,
                  invoiceSearch: _invoiceSearch,
                  onHome: widget.onHome,
                  onAccess: widget.onAccess,
                  onSignOut: _signOut,
                  onSelectTab: (tab) => setState(() => _tab = tab),
                  onSelectAccount: (id) =>
                      setState(() => _selectedBusinessId = id),
                  onSaveProfile: () => _saveProfile(selected),
                  onAddMoment: () => _addBusinessMoment(selected),
                  onInviteRole: (role) => setState(() => _inviteRole = role),
                  onInviteMember: () => _inviteMember(selected),
                  onUpdateMember: (member, role) =>
                      _updateMember(selected, member, role: role),
                  onRemoveMember: (member) =>
                      _updateMember(selected, member, remove: true),
                  onCancelInvite: (member) =>
                      _updateMember(selected, member, cancelInvite: true),
                  onResendInvite: (member) =>
                      _updateMember(selected, member, resendInvite: true),
                  onBuyRoth: () => _requestBusinessRothPurchase(selected, user),
                  onPayInvoice: (invoice, method) =>
                      _payBusinessInvoice(selected, invoice, method),
                  paymentReturnStatus: _returnPaymentStatus,
                  paymentReturnInvoiceId: _returnInvoiceId,
                  paymentReturnInvoice: _returnInvoice,
                  onClearPaymentReturn: () => setState(() {
                    _returnPaymentStatus = '';
                    _returnInvoiceId = '';
                    _returnInvoice = null;
                  }),
                  busy: _busy,
                );
              },
            );
          },
        );
      },
    );
  }

  Map<String, dynamic>? _selectedAccount(List<Map<String, dynamic>> accounts) {
    if (accounts.isEmpty) return null;
    if (_selectedBusinessId.isEmpty) return accounts.first;
    return accounts.cast<Map<String, dynamic>?>().firstWhere(
          (item) =>
              '${item?['id'] ?? item?['businessId'] ?? ''}' ==
              _selectedBusinessId,
          orElse: () => accounts.first,
        );
  }
}

class _BusinessPortalScaffold extends StatelessWidget {
  final User user;
  final List<Map<String, dynamic>> accounts;
  final Map<String, dynamic> selectedAccount;
  final _BusinessPortalTab selectedTab;
  final List<Map<String, dynamic>> deliveries;
  final String message;
  final TextEditingController businessName;
  final TextEditingController contactName;
  final TextEditingController phone;
  final TextEditingController businessAddress;
  final TextEditingController companyNumber;
  final TextEditingController billingEmail;
  final TextEditingController defaultPickupAddress;
  final TextEditingController inviteEmail;
  final TextEditingController inviteName;
  final String inviteRole;
  final TextEditingController invoiceSearch;
  final VoidCallback onHome;
  final VoidCallback onAccess;
  final VoidCallback onSignOut;
  final ValueChanged<_BusinessPortalTab> onSelectTab;
  final ValueChanged<String> onSelectAccount;
  final VoidCallback onSaveProfile;
  final VoidCallback onAddMoment;
  final ValueChanged<String> onInviteRole;
  final VoidCallback onInviteMember;
  final void Function(Map<String, dynamic>, String) onUpdateMember;
  final ValueChanged<Map<String, dynamic>> onRemoveMember;
  final ValueChanged<Map<String, dynamic>> onCancelInvite;
  final ValueChanged<Map<String, dynamic>> onResendInvite;
  final VoidCallback onBuyRoth;
  final void Function(Map<String, dynamic>, String) onPayInvoice;
  final String paymentReturnStatus;
  final String paymentReturnInvoiceId;
  final Map<String, dynamic>? paymentReturnInvoice;
  final VoidCallback onClearPaymentReturn;
  final bool busy;

  const _BusinessPortalScaffold({
    required this.user,
    required this.accounts,
    required this.selectedAccount,
    required this.selectedTab,
    required this.deliveries,
    required this.message,
    required this.businessName,
    required this.contactName,
    required this.phone,
    required this.businessAddress,
    required this.companyNumber,
    required this.billingEmail,
    required this.defaultPickupAddress,
    required this.inviteEmail,
    required this.inviteName,
    required this.inviteRole,
    required this.invoiceSearch,
    required this.onHome,
    required this.onAccess,
    required this.onSignOut,
    required this.onSelectTab,
    required this.onSelectAccount,
    required this.onSaveProfile,
    required this.onAddMoment,
    required this.onInviteRole,
    required this.onInviteMember,
    required this.onUpdateMember,
    required this.onRemoveMember,
    required this.onCancelInvite,
    required this.onResendInvite,
    required this.onBuyRoth,
    required this.onPayInvoice,
    required this.paymentReturnStatus,
    required this.paymentReturnInvoiceId,
    required this.paymentReturnInvoice,
    required this.onClearPaymentReturn,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 980;
    final role = _businessRole(selectedAccount, user);
    final canManage = _businessCanManage(role);
    return Scaffold(
      backgroundColor: const Color(0xff07090f),
      body: _VanguardPageBackground(
        child: SafeArea(
          child: desktop
              ? Row(
                  children: [
                    _BusinessSidebar(
                      onHome: onHome,
                      selectedTab: selectedTab,
                      onSelectTab: onSelectTab,
                      role: role,
                    ),
                    Expanded(child: _main(context, role, canManage, false)),
                  ],
                )
              : _main(context, role, canManage, true),
        ),
      ),
    );
  }

  Widget _main(
      BuildContext context, String role, bool canManage, bool compact) {
    return SingleChildScrollView(
      padding:
          EdgeInsets.fromLTRB(compact ? 18 : 26, 20, compact ? 18 : 30, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BusinessTopBar(
            onHome: compact ? onHome : null,
            onSignOut: onSignOut,
            companyName: '${selectedAccount['businessName'] ?? 'Business'}',
            role: _businessRoleLabel(role),
            accounts: accounts,
            selectedAccountId:
                '${selectedAccount['id'] ?? selectedAccount['businessId'] ?? ''}',
            onSelectAccount: onSelectAccount,
          ),
          const SizedBox(height: 28),
          if (compact) ...[
            _BusinessMobileTabs(
                selectedTab: selectedTab, onSelectTab: onSelectTab, role: role),
            const SizedBox(height: 16),
          ],
          if (message.trim().isNotEmpty) ...[
            _BusinessGlass(
                child: Text(message,
                    style: GoogleFonts.inter(
                        color: Colors.white, fontWeight: FontWeight.w800))),
            const SizedBox(height: 14),
          ],
          if (_statusMessage(selectedAccount).isNotEmpty) ...[
            _BusinessGlass(
                child: Row(children: [
              Icon(_statusIcon(selectedAccount),
                  color: Colors.white.withValues(alpha: 0.9)),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(_statusMessage(selectedAccount),
                      style: GoogleFonts.inter(
                          color: Colors.white,
                          height: 1.4,
                          fontWeight: FontWeight.w800))),
            ])),
            const SizedBox(height: 14),
          ],
          if (selectedTab != _BusinessPortalTab.overview) ...[
            _BusinessEyebrow(_tabEyebrow(selectedTab)),
            const SizedBox(height: 10),
            Text(_tabTitle(selectedTab, selectedAccount),
                style: GoogleFonts.dmSerifDisplay(
                    color: Colors.white,
                    fontSize: compact ? 40 : 54,
                    height: 1.02)),
            const SizedBox(height: 10),
            Text(_tabSubtitle(selectedTab),
                style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 24),
          ],
          if (paymentReturnStatus.isNotEmpty) ...[
            _BusinessPaymentReturnPanel(
              status: paymentReturnStatus,
              invoice: paymentReturnInvoice ??
                  _businessInvoices(selectedAccount).firstWhere(
                    (item) =>
                        '${item['invoiceId'] ?? item['id'] ?? ''}' ==
                        paymentReturnInvoiceId,
                    orElse: () => paymentReturnInvoiceId.isEmpty
                        ? const <String, dynamic>{}
                        : <String, dynamic>{
                            'invoiceId': paymentReturnInvoiceId
                          },
                  ),
              busy: busy,
              rothBalance: _num(selectedAccount['rothBalance'] ??
                  selectedAccount['businessRothBalance']),
              onPayInvoice: onPayInvoice,
              onBackToInvoices: () => onSelectTab(_BusinessPortalTab.invoicing),
              onClear: onClearPaymentReturn,
            ),
            const SizedBox(height: 18),
          ],
          _tabBody(role, canManage, compact),
        ],
      ),
    );
  }

  Widget _tabBody(String role, bool canManage, bool compact) {
    final approved = '${selectedAccount['status'] ?? ''}' == 'approved';
    final canOperate = _businessCanOperate(role) && approved;
    return switch (selectedTab) {
      _BusinessPortalTab.overview => _BusinessOverviewPage(
          account: selectedAccount,
          deliveries: deliveries,
          canOperate: canOperate,
          onAccess: onAccess,
          onOpenInvoices: () => onSelectTab(_BusinessPortalTab.invoicing),
          onOpenTeam: () => onSelectTab(_BusinessPortalTab.team),
          onOpenDeliveries: () => onSelectTab(_BusinessPortalTab.deliveries),
          onOpenHealthPlus: () => onSelectTab(_BusinessPortalTab.healthPlus),
          onOpenGifts: () => onSelectTab(_BusinessPortalTab.gifts),
          onOpenVanguard: () => onSelectTab(_BusinessPortalTab.vanguard),
          onOpenAnalytics: () => onSelectTab(_BusinessPortalTab.analytics),
          onAddMoment: onAddMoment,
          onPayInvoice: onPayInvoice,
          busy: busy),
      _BusinessPortalTab.invoicing => _BusinessInvoicePage(
          account: selectedAccount,
          deliveries: deliveries,
          invoiceSearch: invoiceSearch,
          canManage: _businessCanFinance(role),
          onBuyRoth: onBuyRoth,
          onPayInvoice: onPayInvoice,
          busy: busy),
      _BusinessPortalTab.team => _BusinessTeamPage(
          account: selectedAccount,
          canManage: canManage,
          inviteEmail: inviteEmail,
          inviteName: inviteName,
          inviteRole: inviteRole,
          onInviteRole: onInviteRole,
          onInviteMember: onInviteMember,
          onUpdateMember: onUpdateMember,
          onRemoveMember: onRemoveMember,
          onCancelInvite: onCancelInvite,
          onResendInvite: onResendInvite),
      _BusinessPortalTab.deliveries => _BusinessDeliveriesPage(
          deliveries: deliveries,
          canOperate: canOperate,
          onBookDelivery: onAccess),
      _BusinessPortalTab.healthPlus => _BusinessServicePage(
          title: 'Health+ business',
          icon: Icons.health_and_safety_outlined,
          rows: _healthRows(deliveries),
          canCreate: canOperate,
          onCreate: onAccess),
      _BusinessPortalTab.gifts => _BusinessServicePage(
          title: 'Corporate Gifts',
          icon: Icons.card_giftcard_outlined,
          rows: _giftRows(deliveries),
          canCreate: canOperate,
          onCreate: onAccess),
      _BusinessPortalTab.vanguard => _BusinessServicePage(
          title: 'Vanguard',
          icon: Icons.shield_outlined,
          rows: _vanguardRows(deliveries),
          canCreate: canOperate,
          onCreate: onAccess),
      _BusinessPortalTab.analytics => _BusinessAnalyticsPage(
          deliveries: deliveries, account: selectedAccount),
      _BusinessPortalTab.settings => _BusinessSettingsPage(
          account: selectedAccount,
          canManage: canManage,
          businessName: businessName,
          contactName: contactName,
          phone: phone,
          businessAddress: businessAddress,
          companyNumber: companyNumber,
          billingEmail: billingEmail,
          defaultPickupAddress: defaultPickupAddress,
          onSaveProfile: onSaveProfile,
          onSignOut: onSignOut),
    };
  }

  String _statusMessage(Map<String, dynamic> account) {
    final status = '${account['status'] ?? 'pending'}'.toLowerCase();
    if (status == 'pending') {
      return 'Pending review. Your Business dashboard is ready; booking unlocks after Circum approval.';
    }
    if (status == 'suspended') {
      return 'Account suspended. Your dashboard remains visible, but booking is restricted.';
    }
    return '';
  }

  IconData _statusIcon(Map<String, dynamic> account) {
    final status = '${account['status'] ?? 'pending'}'.toLowerCase();
    return status == 'suspended'
        ? Icons.lock_outline
        : Icons.hourglass_top_rounded;
  }
}

class _BusinessPaymentReturnPanel extends StatelessWidget {
  final String status;
  final Map<String, dynamic> invoice;
  final bool busy;
  final double rothBalance;
  final void Function(Map<String, dynamic>, String) onPayInvoice;
  final VoidCallback onBackToInvoices;
  final VoidCallback onClear;

  const _BusinessPaymentReturnPanel({
    required this.status,
    required this.invoice,
    required this.busy,
    required this.rothBalance,
    required this.onPayInvoice,
    required this.onBackToInvoices,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final success = normalized == 'payment-success';
    final cancelled = normalized == 'payment-cancelled';
    final failed = normalized == 'payment-failed';
    final title = success
        ? 'Payment successful'
        : failed
            ? 'Payment failed'
            : 'Payment was not completed';
    final body = success
        ? 'Your invoice is paid. Your receipt is available from your invoice details.'
        : failed
            ? 'Payment failed. No money was taken.'
            : 'Payment wasn’t completed. Your invoice is still awaiting payment.';
    final icon = success
        ? Icons.check_circle_rounded
        : failed
            ? Icons.error_outline_rounded
            : Icons.info_outline_rounded;
    final color = success
        ? Colors.greenAccent
        : failed
            ? Colors.redAccent
            : Colors.amberAccent;
    final payable = invoice.isNotEmpty && _businessInvoiceIsPayable(invoice);
    return _BusinessGlass(
      borderColor: color.withValues(alpha: 0.42),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900))),
          IconButton(
              onPressed: onClear,
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close_rounded, color: Colors.white)),
        ]),
        const SizedBox(height: 8),
        Text(body,
            style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.74),
                height: 1.45,
                fontWeight: FontWeight.w700)),
        if (invoice.isNotEmpty) ...[
          const SizedBox(height: 12),
          _BusinessBadge(_businessInvoiceDisplayTitle(invoice).toUpperCase()),
        ],
        const SizedBox(height: 14),
        if (success)
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
                onPressed: onBackToInvoices,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('View invoice')),
            OutlinedButton.icon(
                onPressed: onBackToInvoices,
                icon: const Icon(Icons.download_done_rounded),
                label: const Text('Receipt available')),
          ])
        else if (cancelled)
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton(
                onPressed: payable && !busy
                    ? () => onPayInvoice(invoice, 'card')
                    : null,
                child: const Text('Pay Invoice')),
            OutlinedButton(
                onPressed: payable && !busy && rothBalance > 0
                    ? () => onPayInvoice(invoice, 'roth')
                    : null,
                child: const Text('Pay with Roth')),
            OutlinedButton(
                onPressed: payable && !busy
                    ? () => onPayInvoice(invoice, 'part')
                    : null,
                child: const Text('Choose another payment method')),
            TextButton(
                onPressed: onBackToInvoices,
                child: const Text('Back to invoices')),
          ])
        else
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton(
                onPressed: payable && !busy
                    ? () => onPayInvoice(invoice, 'card')
                    : null,
                child: const Text('Try Again')),
            OutlinedButton(
                onPressed: payable && !busy && rothBalance > 0
                    ? () => onPayInvoice(invoice, 'roth')
                    : null,
                child: const Text('Use Roth')),
            OutlinedButton(
                onPressed: () => unawaited(launchUrl(
                    Uri.parse('mailto:support@circumuk.com'),
                    webOnlyWindowName: '_self')),
                child: const Text('Contact Support')),
            TextButton(
                onPressed: onBackToInvoices,
                child: const Text('Back to invoices')),
          ])
      ]),
    );
  }
}

class _BusinessOverviewPage extends StatelessWidget {
  final Map<String, dynamic> account;
  final List<Map<String, dynamic>> deliveries;
  final bool canOperate;
  final VoidCallback onAccess;
  final VoidCallback onOpenInvoices;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenDeliveries;
  final VoidCallback onOpenHealthPlus;
  final VoidCallback onOpenGifts;
  final VoidCallback onOpenVanguard;
  final VoidCallback onOpenAnalytics;
  final VoidCallback onAddMoment;
  final void Function(Map<String, dynamic>, String) onPayInvoice;
  final bool busy;

  const _BusinessOverviewPage(
      {required this.account,
      required this.deliveries,
      required this.canOperate,
      required this.onAccess,
      required this.onOpenInvoices,
      required this.onOpenTeam,
      required this.onOpenDeliveries,
      required this.onOpenHealthPlus,
      required this.onOpenGifts,
      required this.onOpenVanguard,
      required this.onOpenAnalytics,
      required this.onAddMoment,
      required this.onPayInvoice,
      required this.busy});

  @override
  Widget build(BuildContext context) {
    final invoices = _businessInvoices(account);
    final activeDeliveries =
        deliveries.where((item) => _businessStatusGroup(item) == 'active');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BusinessDashboardHero(),
        const SizedBox(height: 18),
        _BusinessOverviewMetrics(
            account: account,
            deliveries: deliveries,
            invoices: invoices,
            activeDeliveries: activeDeliveries.length),
        const SizedBox(height: 18),
        _BusinessEcosystemCards(
          onOpenDeliveries: onOpenDeliveries,
          onOpenGifts: onOpenGifts,
          onOpenHealthPlus: onOpenHealthPlus,
          onOpenMoments: onAddMoment,
          onOpenVanguard: onOpenVanguard,
          onOpenAnalytics: onOpenAnalytics,
        ),
        const SizedBox(height: 18),
        _BusinessIrisMomentsPanel(
          account: account,
          canOperate: canOperate,
          onAddMoment: onAddMoment,
          onSendGift: onOpenGifts,
          onCreateDelivery: onAccess,
          onScheduleHealthPlus: onOpenHealthPlus,
        ),
        const SizedBox(height: 18),
        _BusinessRecentActivityFeed(
            account: account, deliveries: deliveries, invoices: invoices),
        const SizedBox(height: 18),
        _BusinessActiveDeliveryCards(
          deliveries: activeDeliveries.take(4).toList(growable: false),
          canOperate: canOperate,
          onBookDelivery: onAccess,
        ),
        const SizedBox(height: 18),
        _BusinessQuickActions(
          canOperate: canOperate,
          onNewDelivery: onAccess,
          onSendGift: onOpenGifts,
          onHealthPlus: onOpenHealthPlus,
          onCreateInvoice: onOpenInvoices,
          onInviteTeam: onOpenTeam,
          onAddMoment: onAddMoment,
        ),
        const SizedBox(height: 18),
        _BusinessOverviewInvoicesTable(
          account: account,
          invoices: invoices,
          busy: busy,
          onOpenInvoices: onOpenInvoices,
          onPayInvoice: onPayInvoice,
        ),
      ],
    );
  }
}

class _BusinessDashboardHero extends StatelessWidget {
  const _BusinessDashboardHero();

  @override
  Widget build(BuildContext context) => _BusinessGlass(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BusinessEyebrow('Business Centre'),
                  const SizedBox(height: 10),
                  Text('Your Business Centre',
                      style: GoogleFonts.dmSerifDisplay(
                          color: Colors.white, fontSize: 54, height: 1)),
                  const SizedBox(height: 10),
                  Text('Everything your business needs in one place.',
                      style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 16,
                          height: 1.45,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                        colors: [Color(0xff3b82f6), Color(0xff60a5fa)]),
                    boxShadow: [
                      BoxShadow(
                          color:
                              const Color(0xff3b82f6).withValues(alpha: 0.38),
                          blurRadius: 46)
                    ]),
                child: const Icon(Icons.business_center_rounded,
                    color: Colors.white, size: 32)),
          ],
        ),
      );
}

class _BusinessOverviewMetrics extends StatelessWidget {
  final Map<String, dynamic> account;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> invoices;
  final int activeDeliveries;

  const _BusinessOverviewMetrics({
    required this.account,
    required this.deliveries,
    required this.invoices,
    required this.activeDeliveries,
  });

  @override
  Widget build(BuildContext context) {
    final outstanding = invoices.fold<double>(
        0,
        (total, invoice) => _businessInvoiceIsPayable(invoice)
            ? total + _num(invoice['balanceDue'] ?? invoice['total'])
            : total);
    final stats = [
      _BusinessStatCard(
          label: 'Roth Balance',
          value:
              '${_num(account['rothBalance'] ?? account['businessRothBalance']).toStringAsFixed(2)}',
          note: 'Available to use',
          icon: Icons.account_balance_wallet_outlined),
      _BusinessStatCard(
          label: 'Invoices',
          value: '£${outstanding.toStringAsFixed(2)}',
          note: outstanding > 0 ? 'Outstanding' : 'No payment due',
          icon: Icons.receipt_long_outlined),
      _BusinessStatCard(
          label: 'Active Jobs',
          value: '$activeDeliveries',
          note: 'In progress',
          icon: Icons.local_shipping_outlined),
      _BusinessStatCard(
          label: 'Team Members',
          value: '${_businessMembers(account).length}',
          note: 'People with access',
          icon: Icons.groups_2_outlined),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth < 760 ? 1 : 4;
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: columns == 1 ? 4.0 : 2.05,
        children: stats,
      );
    });
  }
}

class _BusinessEcosystemCards extends StatelessWidget {
  final VoidCallback onOpenDeliveries;
  final VoidCallback onOpenGifts;
  final VoidCallback onOpenHealthPlus;
  final VoidCallback onOpenMoments;
  final VoidCallback onOpenVanguard;
  final VoidCallback onOpenAnalytics;

  const _BusinessEcosystemCards({
    required this.onOpenDeliveries,
    required this.onOpenGifts,
    required this.onOpenHealthPlus,
    required this.onOpenMoments,
    required this.onOpenVanguard,
    required this.onOpenAnalytics,
  });

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        Icons.local_shipping_outlined,
        'Deliveries',
        'Book, track and manage deliveries.',
        onOpenDeliveries
      ),
      (
        Icons.card_giftcard_outlined,
        'Business Gifts',
        'Send thoughtful gifts from your company.',
        onOpenGifts
      ),
      (
        Icons.health_and_safety_outlined,
        'Health+',
        'Arrange trusted medical deliveries.',
        onOpenHealthPlus
      ),
      (
        Icons.auto_awesome_outlined,
        'IRIS Moments',
        'Turn people, dates and reminders into thoughtful actions.',
        onOpenMoments
      ),
      (
        Icons.shield_outlined,
        'Vanguard',
        'Add extra care for sensitive deliveries.',
        onOpenVanguard
      ),
      (
        Icons.query_stats_outlined,
        'Analytics',
        'See spend and delivery trends.',
        onOpenAnalytics
      ),
    ];
    return _BusinessGlass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _BusinessPanelHeader(
            title: 'Your Circum Ecosystem',
            subtitle:
                'One Business account for everything your company sends.'),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth < 720 ? 1 : 3;
          return GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: columns == 1 ? 3.6 : 1.62,
            children: cards
                .map((card) => _BusinessEcosystemCard(
                      icon: card.$1,
                      title: card.$2,
                      body: card.$3,
                      onTap: card.$4,
                    ))
                .toList(growable: false),
          );
        })
      ]),
    );
  }
}

class _BusinessEcosystemCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _BusinessEcosystemCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: const Color(0xff3b82f6), size: 24),
            const Spacer(),
            Text(title,
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _BusinessIrisMomentsPanel extends StatelessWidget {
  final Map<String, dynamic> account;
  final bool canOperate;
  final VoidCallback onAddMoment;
  final VoidCallback onSendGift;
  final VoidCallback onCreateDelivery;
  final VoidCallback onScheduleHealthPlus;

  const _BusinessIrisMomentsPanel({
    required this.account,
    required this.canOperate,
    required this.onAddMoment,
    required this.onSendGift,
    required this.onCreateDelivery,
    required this.onScheduleHealthPlus,
  });

  @override
  Widget build(BuildContext context) {
    final moments = _businessMoments(account);
    final openMoments = moments
        .where((moment) => _momentStatus(moment) != 'completed')
        .toList(growable: false);
    final thisWeekMoments = openMoments
        .where((moment) => {'today', 'week'}.contains(_momentBucket(moment)))
        .toList(growable: false);
    final giftOpportunities =
        thisWeekMoments.where(_momentIsGiftOpportunity).length;
    final healthReminders = thisWeekMoments.where(_momentIsHealth).length;
    final deliveryReminders = thisWeekMoments.where(_momentIsDelivery).length;
    final completed = moments
        .where((moment) => _momentStatus(moment) == 'completed')
        .take(3)
        .toList(growable: false);
    final today = openMoments
        .where((moment) => _momentBucket(moment) == 'today')
        .toList(growable: false);
    final thisWeek = openMoments
        .where((moment) => _momentBucket(moment) == 'week')
        .toList(growable: false);
    final thisMonth = openMoments
        .where((moment) => _momentBucket(moment) == 'month')
        .toList(growable: false);
    final suggested = [...openMoments]..sort((a, b) =>
        _momentRecommendationConfidence(b, moments)
            .compareTo(_momentRecommendationConfidence(a, moments)));
    final businessName =
        '${account['businessName'] ?? account['companyName'] ?? 'your business'}'
            .trim();

    return _BusinessGlass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Expanded(
            child: _BusinessPanelHeader(
              title: 'IRIS Moments',
              subtitle:
                  'Relationship intelligence for birthdays, renewals, Health+ reminders and company milestones.',
            ),
          ),
          FilledButton.icon(
            onPressed: canOperate ? onAddMoment : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Moment'),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xff0d1b2e).withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
                color: const Color(0xff60a5fa).withValues(alpha: 0.20)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xff3b82f6).withValues(alpha: 0.10),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${_businessTimeGreeting()}, $businessName.',
              style: GoogleFonts.dmSerifDisplay(
                color: Colors.white,
                fontSize: 28,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'IRIS has reviewed your upcoming moments.',
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'This week you have:',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _BusinessIrisMetricCard(
                  value: '${thisWeekMoments.length}',
                  label: 'Upcoming Moments'),
              _BusinessIrisMetricCard(
                  value: '$giftOpportunities', label: 'Gift Opportunities'),
              _BusinessIrisMetricCard(
                  value: '$healthReminders', label: 'Health+ Reminder'),
              _BusinessIrisMetricCard(
                  value: '$deliveryReminders', label: 'Delivery Reminder'),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        if (moments.isEmpty)
          _BusinessIrisMomentsEmpty(onAddMoment: onAddMoment)
        else ...[
          LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 860;
            final summary = [
              _BusinessMomentBucket(
                title: 'Today',
                moments: today,
                emptyText: 'No moments today.',
              ),
              _BusinessMomentBucket(
                title: 'This Week',
                moments: thisWeek,
                emptyText: 'Nothing due this week.',
              ),
              _BusinessMomentBucket(
                title: 'This Month',
                moments: thisMonth,
                emptyText: 'No later moments this month.',
              ),
            ];
            return compact
                ? Column(
                    children: summary
                        .map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: item,
                            ))
                        .toList(growable: false),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: summary
                        .map((item) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: item,
                              ),
                            ))
                        .toList(growable: false),
                  );
          }),
          const SizedBox(height: 16),
          Text('IRIS Recommendations',
              style: GoogleFonts.inter(
                  color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (suggested.isEmpty)
            const _BusinessEmptyState(
                'No recommendations are ready yet. IRIS will act once a moment becomes relevant.')
          else
            ...suggested.take(5).map((moment) => _BusinessMomentSuggestion(
                  moment: moment,
                  allMoments: moments,
                  onSendGift: onSendGift,
                  onCreateDelivery: onCreateDelivery,
                  onScheduleHealthPlus: onScheduleHealthPlus,
                  onCreateReminder: onAddMoment,
                )),
          const SizedBox(height: 16),
          _BusinessRelationshipHealth(
            moments: moments,
            onSendGift: onSendGift,
            onCreateDelivery: onCreateDelivery,
            onDismiss: onAddMoment,
          ),
          const SizedBox(height: 16),
          Text('Recently Completed',
              style: GoogleFonts.inter(
                  color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (completed.isEmpty)
            const _BusinessEmptyState(
                'Completed gifts, deliveries, cards and reminders will appear here.')
          else
            ...completed.map((moment) => _BusinessMomentLine(moment: moment)),
        ],
      ]),
    );
  }
}

class _BusinessIrisMetricCard extends StatelessWidget {
  final String value;
  final String label;

  const _BusinessIrisMetricCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: GoogleFonts.jetBrainsMono(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.64),
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ]),
      );
}

class _BusinessIrisMomentsEmpty extends StatelessWidget {
  final VoidCallback onAddMoment;

  const _BusinessIrisMomentsEmpty({required this.onAddMoment});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('No upcoming moments.',
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            'Create important moments once and let IRIS remind you at the right time with intelligent Circum recommendations.',
            style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.68),
                height: 1.42,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onAddMoment,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add First Moment'),
          ),
        ]),
      );
}

class _BusinessMomentBucket extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> moments;
  final String emptyText;

  const _BusinessMomentBucket({
    required this.title,
    required this.moments,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_awesome_outlined,
                color: const Color(0xff3b82f6), size: 18),
            const SizedBox(width: 8),
            Text(title,
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 10),
          if (moments.isEmpty)
            Text(emptyText,
                style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700))
          else
            ...moments.take(3).map((moment) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BusinessMomentLine(moment: moment),
                )),
        ]),
      );
}

class _BusinessMomentLine extends StatelessWidget {
  final Map<String, dynamic> moment;

  const _BusinessMomentLine({required this.moment});

  @override
  Widget build(BuildContext context) {
    final name = _momentName(moment);
    final type = _momentTypeLabel(moment);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 7),
        decoration: const BoxDecoration(
            color: Color(0xff60a5fa), shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: Colors.white, fontWeight: FontWeight.w900)),
          Text('$type · ${_momentDateLabel(moment)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    ]);
  }
}

class _BusinessMomentSuggestion extends StatelessWidget {
  final Map<String, dynamic> moment;
  final List<Map<String, dynamic>> allMoments;
  final VoidCallback onSendGift;
  final VoidCallback onCreateDelivery;
  final VoidCallback onScheduleHealthPlus;
  final VoidCallback onCreateReminder;

  const _BusinessMomentSuggestion({
    required this.moment,
    required this.allMoments,
    required this.onSendGift,
    required this.onCreateDelivery,
    required this.onScheduleHealthPlus,
    required this.onCreateReminder,
  });

  @override
  Widget build(BuildContext context) {
    final recommendation = _momentRecommendation(moment, allMoments);
    final confidence = _momentRecommendationConfidence(moment, allMoments);
    final confidenceLabel = confidence >= 0.82
        ? 'High confidence'
        : confidence >= 0.66
            ? 'Medium confidence'
            : 'Low confidence';
    final service = _momentRecommendedService(moment);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.052),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.psychology_alt_outlined,
              color: Color(0xff60a5fa), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(recommendation.$1,
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w900)),
          ),
          _BusinessBadge(_momentCountdown(moment).toUpperCase()),
        ]),
        const SizedBox(height: 8),
        Text(service,
            style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(recommendation.$2,
            style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.68),
                height: 1.42,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _BusinessBadge(confidenceLabel),
          _BusinessBadge(
              'WHY: ${_momentWhy(moment, allMoments).toUpperCase()}'),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (_momentIsGiftOpportunity(moment)) ...[
            OutlinedButton.icon(
                onPressed: onSendGift,
                icon: const Icon(Icons.card_giftcard_outlined),
                label: const Text('Open Gift Portal')),
            OutlinedButton.icon(
                onPressed: onSendGift,
                icon: const Icon(Icons.mail_outline_rounded),
                label: const Text('Send Card')),
          ] else if (_momentIsHealth(moment))
            OutlinedButton.icon(
                onPressed: onScheduleHealthPlus,
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('Launch Health+ Delivery'))
          else if (_momentIsDelivery(moment))
            OutlinedButton.icon(
                onPressed: onCreateDelivery,
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Launch Delivery'))
          else
            OutlinedButton.icon(
                onPressed: onCreateReminder,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Create Reminder')),
          OutlinedButton.icon(
              onPressed: onCreateReminder,
              icon: const Icon(Icons.today_outlined),
              label: const Text('Remind Tomorrow')),
          OutlinedButton.icon(
              onPressed: onCreateReminder,
              icon: const Icon(Icons.snooze_outlined),
              label: const Text('Snooze')),
          OutlinedButton.icon(
              onPressed: onCreateReminder,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Dismiss')),
        ])
      ]),
    );
  }
}

class _BusinessRelationshipHealth extends StatelessWidget {
  final List<Map<String, dynamic>> moments;
  final VoidCallback onSendGift;
  final VoidCallback onCreateDelivery;
  final VoidCallback onDismiss;

  const _BusinessRelationshipHealth({
    required this.moments,
    required this.onSendGift,
    required this.onCreateDelivery,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final relationships = _relationshipHealthRows(moments).take(3).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Relationship Health',
          style: GoogleFonts.inter(
              color: Colors.white, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      if (relationships.isEmpty)
        const _BusinessEmptyState(
            'IRIS will surface relationship health once moments or completed actions exist.')
      else
        ...relationships.map((row) => _BusinessRelationshipHealthCard(
              row: row,
              onSendGift: onSendGift,
              onCreateDelivery: onCreateDelivery,
              onDismiss: onDismiss,
            )),
    ]);
  }
}

class _BusinessRelationshipHealthCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onSendGift;
  final VoidCallback onCreateDelivery;
  final VoidCallback onDismiss;

  const _BusinessRelationshipHealthCard({
    required this.row,
    required this.onSendGift,
    required this.onCreateDelivery,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.046),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${row['name']}',
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w900)),
            ),
            _BusinessBadge('${row['status']}'),
          ]),
          const SizedBox(height: 6),
          Text('${row['detail']}',
              style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.66),
                  height: 1.4,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text('IRIS: "${row['insight']}"',
              style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.78),
                  height: 1.4,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: onSendGift,
                icon: const Icon(Icons.card_giftcard_outlined),
                label: const Text('Open Gift Portal')),
            OutlinedButton.icon(
                onPressed: onCreateDelivery,
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Launch Delivery')),
            OutlinedButton.icon(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Dismiss')),
          ])
        ]),
      );
}

class _BusinessRecentActivityFeed extends StatelessWidget {
  final Map<String, dynamic> account;
  final List<Map<String, dynamic>> deliveries;
  final List<Map<String, dynamic>> invoices;

  const _BusinessRecentActivityFeed({
    required this.account,
    required this.deliveries,
    required this.invoices,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[];
    final paidInvoices = invoices.where((item) => {
          'paid',
          'paid_manually',
          'paid_with_roth'
        }.contains(_businessInvoiceStatus(item)));
    final paidInvoice = paidInvoices.isEmpty ? null : paidInvoices.first;
    if (paidInvoice != null) {
      items.add((
        Icons.receipt_long_outlined,
        'Invoice paid',
        _businessInvoiceDisplayTitle(paidInvoice)
      ));
    }
    final pickedUpRows = deliveries.where((item) =>
        '${item['status'] ?? ''}'.toLowerCase().contains('pickup') ||
        '${item['status'] ?? ''}'.toLowerCase().contains('picked'));
    final pickedUp = pickedUpRows.isEmpty ? null : pickedUpRows.first;
    if (pickedUp != null) {
      items.add((
        Icons.inventory_2_outlined,
        'Delivery picked up',
        '${pickedUp['trackingReference'] ?? pickedUp['id'] ?? 'Delivery'}'
      ));
    }
    final giftRows = deliveries.where((item) =>
        _businessPillar(item) == 'Gifts' &&
        _businessStatusGroup(item) == 'completed');
    final gift = giftRows.isEmpty ? null : giftRows.first;
    if (gift != null) {
      items.add((
        Icons.card_giftcard_outlined,
        'Gift delivered',
        '${gift['trackingReference'] ?? gift['id'] ?? 'Gift'}'
      ));
    }
    final healthRows =
        deliveries.where((item) => _businessPillar(item) == 'Health+');
    final health = healthRows.isEmpty ? null : healthRows.first;
    if (health != null) {
      items.add((
        Icons.health_and_safety_outlined,
        'Health+ renewed',
        '${health['trackingReference'] ?? health['id'] ?? 'Health+'}'
      ));
    }
    final invitedRows = _businessMembers(account)
        .where((item) => '${item['status'] ?? ''}' == 'invited');
    final invited = invitedRows.isEmpty ? null : invitedRows.first;
    if (invited != null) {
      items.add((
        Icons.person_add_alt_1_outlined,
        'Team member invited',
        '${invited['email'] ?? invited['name'] ?? 'Team member'}'
      ));
    }
    return _BusinessGlass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _BusinessPanelHeader(
            title: 'Recent Activity',
            subtitle: 'Invoices, deliveries, gifts, Health+ and team updates.'),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const _BusinessEmptyState(
              'Your latest invoices, deliveries and team updates will appear here.')
        else
          ...items.take(5).map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Icon(item.$1, color: const Color(0xff3b82f6), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(item.$2,
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w900))),
                  Text(item.$3,
                      style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w700)),
                ]),
              ))
      ]),
    );
  }
}

class _BusinessActiveDeliveryCards extends StatelessWidget {
  final List<Map<String, dynamic>> deliveries;
  final bool canOperate;
  final VoidCallback onBookDelivery;

  const _BusinessActiveDeliveryCards({
    required this.deliveries,
    required this.canOperate,
    required this.onBookDelivery,
  });

  @override
  Widget build(BuildContext context) => _BusinessGlass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _BusinessPanelHeader(
              title: 'Active Deliveries',
              subtitle: 'Open any delivery to see the full tracking page.'),
          const SizedBox(height: 12),
          if (deliveries.isEmpty)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _BusinessEmptyState(
                  'You do not have any active deliveries right now.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                  onPressed: canOperate ? onBookDelivery : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New Delivery')),
            ])
          else
            ...deliveries.map((delivery) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BusinessActiveDeliveryCard(delivery: delivery),
                )),
        ]),
      );
}

class _BusinessActiveDeliveryCard extends StatelessWidget {
  final Map<String, dynamic> delivery;

  const _BusinessActiveDeliveryCard({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final pickup =
        '${delivery['pickupAddress'] ?? delivery['pickup'] ?? 'Pickup'}';
    final dropoff =
        '${delivery['dropoffAddress'] ?? delivery['dropoff'] ?? 'Drop-off'}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10))),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 170,
            child: Text(
                '${delivery['trackingReference'] ?? delivery['id'] ?? delivery['requestId'] ?? 'Delivery'}',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                    color: Colors.white, fontWeight: FontWeight.w900)),
          ),
          _BusinessBadge(_businessPillar(delivery).toUpperCase()),
          SizedBox(
            width: 280,
            child: Text('$pickup → $dropoff',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.74),
                    fontWeight: FontWeight.w700)),
          ),
          _BusinessBadge('${delivery['status'] ?? 'pending'}'.toUpperCase()),
          Text('£${_businessAmount(delivery).toStringAsFixed(2)}',
              style: GoogleFonts.jetBrainsMono(
                  color: Colors.white, fontWeight: FontWeight.w900)),
          TextButton(
              onPressed: () => _openBusinessTracking(delivery),
              child: const Text('View')),
        ],
      ),
    );
  }
}

class _BusinessQuickActions extends StatelessWidget {
  final bool canOperate;
  final VoidCallback onNewDelivery;
  final VoidCallback onSendGift;
  final VoidCallback onHealthPlus;
  final VoidCallback onCreateInvoice;
  final VoidCallback onInviteTeam;
  final VoidCallback onAddMoment;

  const _BusinessQuickActions({
    required this.canOperate,
    required this.onNewDelivery,
    required this.onSendGift,
    required this.onHealthPlus,
    required this.onCreateInvoice,
    required this.onInviteTeam,
    required this.onAddMoment,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        Icons.add_road_rounded,
        'New Delivery',
        canOperate ? onNewDelivery : null
      ),
      (
        Icons.card_giftcard_outlined,
        'Send Business Gift',
        canOperate ? onSendGift : null
      ),
      (
        Icons.health_and_safety_outlined,
        'Health+ Delivery',
        canOperate ? onHealthPlus : null
      ),
      (Icons.receipt_long_outlined, 'Create Invoice', onCreateInvoice),
      (Icons.person_add_alt_1_outlined, 'Invite Team Member', onInviteTeam),
      (
        Icons.auto_awesome_outlined,
        'Add Moment',
        canOperate ? onAddMoment : null
      ),
    ];
    return _BusinessGlass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _BusinessPanelHeader(
            title: 'Quick Actions',
            subtitle: 'Start the next thing your company needs.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: actions
              .map((item) => OutlinedButton.icon(
                    onPressed: item.$3,
                    icon: Icon(item.$1),
                    label: Text(item.$2),
                  ))
              .toList(growable: false),
        )
      ]),
    );
  }
}

class _BusinessOverviewInvoicesTable extends StatelessWidget {
  final Map<String, dynamic> account;
  final List<Map<String, dynamic>> invoices;
  final bool busy;
  final VoidCallback onOpenInvoices;
  final void Function(Map<String, dynamic>, String) onPayInvoice;

  const _BusinessOverviewInvoicesTable({
    required this.account,
    required this.invoices,
    required this.busy,
    required this.onOpenInvoices,
    required this.onPayInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final rows = invoices.take(6).toList(growable: false);
    return _BusinessGlass(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: _BusinessPanelHeader(
                  title: 'Invoices',
                  subtitle: 'Review and pay your Business invoices.')),
          TextButton(onPressed: onOpenInvoices, child: const Text('View all')),
        ]),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const _BusinessEmptyState(
              'You do not have any Business invoices yet.')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: GoogleFonts.jetBrainsMono(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 11,
                  fontWeight: FontWeight.w800),
              dataTextStyle: GoogleFonts.inter(
                  color: Colors.white, fontWeight: FontWeight.w700),
              columns: const [
                DataColumn(label: Text('Invoice number')),
                DataColumn(label: Text('Customer')),
                DataColumn(label: Text('Issue date')),
                DataColumn(label: Text('Due date')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Pay Invoice')),
              ],
              rows: rows
                  .map((invoice) => DataRow(cells: [
                        DataCell(Text(_businessInvoiceDisplayTitle(invoice))),
                        DataCell(Text(
                            '${invoice['customerName'] ?? account['businessName'] ?? 'Business'}')),
                        DataCell(Text(_businessDateLabel(_businessDate({
                          'createdAt':
                              invoice['issueDate'] ?? invoice['createdAt']
                        })))),
                        DataCell(Text(_businessDateLabel(
                            _businessDate({'dueDate': invoice['dueDate']})))),
                        DataCell(Text(
                            '£${_num(invoice['balanceDue'] ?? invoice['total']).toStringAsFixed(2)}')),
                        DataCell(_BusinessBadge(
                            _businessInvoiceCustomerStatus(invoice)
                                .toUpperCase())),
                        DataCell(FilledButton(
                          onPressed: !busy && _businessInvoiceIsPayable(invoice)
                              ? () => onPayInvoice(invoice, 'card')
                              : null,
                          child: Text(_businessInvoiceIsPayable(invoice)
                              ? 'Pay Invoice'
                              : _businessInvoiceCustomerStatus(invoice)),
                        )),
                      ]))
                  .toList(growable: false),
            ),
          ),
      ]),
    );
  }
}

class _BusinessAuthGate extends StatelessWidget {
  final bool signupMode;
  final bool busy;
  final String message;
  final TextEditingController email;
  final TextEditingController password;
  final VoidCallback onToggleMode;
  final VoidCallback onSubmit;
  final VoidCallback onResetPassword;
  final VoidCallback onHome;

  const _BusinessAuthGate(
      {required this.signupMode,
      required this.busy,
      required this.message,
      required this.email,
      required this.password,
      required this.onToggleMode,
      required this.onSubmit,
      required this.onResetPassword,
      required this.onHome});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff07090f),
      body: Stack(children: [
        const Positioned(
            top: -140,
            right: -120,
            child: _BusinessGlow(size: 420, color: Color(0xff3b82f6))),
        Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _BusinessGlass(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      IconButton(
                          onPressed: onHome,
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white)),
                      const _BusinessEyebrow('Business Accounts'),
                      const SizedBox(height: 10),
                      Text(
                          signupMode
                              ? 'Create your Business login.'
                              : 'Business login.',
                          style: GoogleFonts.dmSerifDisplay(
                              color: Colors.white, fontSize: 42, height: 1.02)),
                      const SizedBox(height: 10),
                      Text(
                          'Sign in to access the Business Account dashboard. Your session stays active across refreshes.',
                          style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.72),
                              height: 1.45,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 18),
                      _BusinessTextField(controller: email, label: 'Email'),
                      const SizedBox(height: 10),
                      _BusinessTextField(
                          controller: password,
                          label: 'Password',
                          obscure: true),
                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(message,
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w800))
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: busy ? null : onSubmit,
                              child: Text(signupMode
                                  ? 'Register business account'
                                  : 'Sign in'))),
                      const SizedBox(height: 10),
                      Wrap(spacing: 12, children: [
                        TextButton(
                            onPressed: onToggleMode,
                            child: Text(signupMode
                                ? 'I already have a login'
                                : 'Register business account')),
                        TextButton(
                            onPressed: onResetPassword,
                            child: const Text('Reset password'))
                      ]),
                    ]))))
      ]),
    );
  }
}

class _BusinessOnboardingPage extends StatelessWidget {
  final String message;
  final TextEditingController businessName;
  final TextEditingController contactName;
  final TextEditingController phone;
  final TextEditingController businessAddress;
  final TextEditingController companyNumber;
  final TextEditingController billingEmail;
  final TextEditingController defaultPickupAddress;
  final VoidCallback onCreate;
  final VoidCallback onSignOut;

  const _BusinessOnboardingPage(
      {required this.message,
      required this.businessName,
      required this.contactName,
      required this.phone,
      required this.businessAddress,
      required this.companyNumber,
      required this.billingEmail,
      required this.defaultPickupAddress,
      required this.onCreate,
      required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xff07090f),
        body: Center(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: _BusinessGlass(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            const _BusinessBadge('BUSINESS'),
                            const Spacer(),
                            TextButton.icon(
                                onPressed: onSignOut,
                                icon: const Icon(Icons.logout),
                                label: const Text('Sign out'))
                          ]),
                          const SizedBox(height: 14),
                          Text('Create your business profile.',
                              style: GoogleFonts.dmSerifDisplay(
                                  color: Colors.white,
                                  fontSize: 44,
                                  height: 1.02)),
                          const SizedBox(height: 10),
                          Text(
                              'Business accounts are reviewed by Circum before booking is enabled.',
                              style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 18),
                          _BusinessTextField(
                              controller: businessName, label: 'Business name'),
                          _BusinessTextField(
                              controller: contactName, label: 'Contact name'),
                          _BusinessTextField(controller: phone, label: 'Phone'),
                          _AddressField(
                            colors: const _CircumColors(true),
                            icon: Icons.business_outlined,
                            label: 'Business address',
                            controller: businessAddress,
                            glassStyle: true,
                            onSelected: (address) =>
                                businessAddress.text = address.displayAddress,
                          ),
                          const SizedBox(height: 10),
                          _BusinessTextField(
                              controller: companyNumber,
                              label: 'VAT / company number optional'),
                          _BusinessTextField(
                              controller: billingEmail, label: 'Billing email'),
                          _AddressField(
                            colors: const _CircumColors(true),
                            icon: Icons.radio_button_checked,
                            label: 'Default pickup address',
                            controller: defaultPickupAddress,
                            glassStyle: true,
                            onSelected: (address) => defaultPickupAddress.text =
                                address.displayAddress,
                          ),
                          const SizedBox(height: 10),
                          if (message.isNotEmpty)
                            Text(message,
                                style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800)),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                              onPressed: onCreate,
                              icon: const Icon(Icons.add_business_rounded),
                              label: const Text('Register business account')),
                        ]))))));
  }
}

class _BusinessSidebar extends StatelessWidget {
  final VoidCallback onHome;
  final _BusinessPortalTab selectedTab;
  final ValueChanged<_BusinessPortalTab> onSelectTab;
  final String role;

  const _BusinessSidebar(
      {required this.onHome,
      required this.selectedTab,
      required this.onSelectTab,
      required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 282,
      margin: const EdgeInsets.all(18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
            onTap: onHome,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(children: [
                  Image.asset('assets/images/circum_wordmark.png',
                      width: 126, height: 30, fit: BoxFit.contain),
                  const Spacer(),
                  const _BusinessBadge('BUSINESS')
                ]))),
        const SizedBox(height: 28),
        _BusinessNavGroup(
            title: 'Account',
            selectedTab: selectedTab,
            onSelectTab: onSelectTab,
            items: const [
              (
                Icons.dashboard_outlined,
                'Overview',
                _BusinessPortalTab.overview
              ),
              (
                Icons.receipt_long_outlined,
                'Invoicing',
                _BusinessPortalTab.invoicing
              ),
              (Icons.group_outlined, 'Team & access', _BusinessPortalTab.team)
            ]),
        const SizedBox(height: 22),
        _BusinessNavGroup(
            title: 'Ecosystem',
            selectedTab: selectedTab,
            onSelectTab: onSelectTab,
            items: const [
              (
                Icons.local_shipping_outlined,
                'Deliveries',
                _BusinessPortalTab.deliveries
              ),
              (
                Icons.health_and_safety_outlined,
                'Health+',
                _BusinessPortalTab.healthPlus
              ),
              (Icons.card_giftcard_outlined, 'Gifts', _BusinessPortalTab.gifts),
              (Icons.shield_outlined, 'Vanguard', _BusinessPortalTab.vanguard)
            ]),
        const SizedBox(height: 22),
        _BusinessNavGroup(
            title: 'System',
            selectedTab: selectedTab,
            onSelectTab: onSelectTab,
            items: const [
              (
                Icons.analytics_outlined,
                'Analytics',
                _BusinessPortalTab.analytics
              ),
              (Icons.settings_outlined, 'Settings', _BusinessPortalTab.settings)
            ]),
        const Spacer(),
        _BusinessTierCard(deliveries: const []),
      ]),
    );
  }
}

class _BusinessTopBar extends StatelessWidget {
  final VoidCallback? onHome;
  final VoidCallback onSignOut;
  final String companyName;
  final String role;
  final List<Map<String, dynamic>> accounts;
  final String selectedAccountId;
  final ValueChanged<String> onSelectAccount;

  const _BusinessTopBar(
      {this.onHome,
      required this.onSignOut,
      required this.companyName,
      required this.role,
      required this.accounts,
      required this.selectedAccountId,
      required this.onSelectAccount});

  @override
  Widget build(BuildContext context) {
    return Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (onHome != null)
            IconButton.filledTonal(
                onPressed: onHome,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back to Circum'),
          Container(
              width: math.min(MediaQuery.sizeOf(context).width - 44, 430),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.10))),
              child: Row(children: [
                Icon(Icons.search, color: Colors.white.withValues(alpha: 0.62)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('Search jobs, invoices, riders…',
                        style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontWeight: FontWeight.w600)))
              ])),
          if (accounts.length > 1)
            DropdownButton<String>(
                value: selectedAccountId,
                dropdownColor: const Color(0xff111827),
                style: const TextStyle(color: Colors.white),
                items: accounts
                    .map((account) => DropdownMenuItem(
                        value:
                            '${account['id'] ?? account['businessId'] ?? ''}',
                        child:
                            Text('${account['businessName'] ?? 'Business'}')))
                    .toList(),
                onChanged: (value) {
                  if (value != null) onSelectAccount(value);
                }),
          IconButton.filledTonal(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded),
              tooltip: 'Notifications'),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.065),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.10))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                    radius: 17,
                    backgroundColor: const Color(0xff3b82f6),
                    child: Text(
                        companyName.isEmpty
                            ? 'B'
                            : companyName.characters.first.toUpperCase(),
                        style: const TextStyle(color: Colors.white))),
                const SizedBox(width: 9),
                Text('$companyName · $role',
                    style: GoogleFonts.inter(
                        color: Colors.white, fontWeight: FontWeight.w800))
              ])),
          TextButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Logout')),
        ]);
  }
}

class _BusinessStatsGrid extends StatelessWidget {
  final List<Map<String, dynamic>> deliveries;
  final Map<String, dynamic> account;

  const _BusinessStatsGrid({
    this.deliveries = const [],
    this.account = const {},
  });

  @override
  Widget build(BuildContext context) {
    final active = deliveries
        .where((item) => _businessStatusGroup(item) == 'active')
        .length;
    final week = deliveries
        .where((item) =>
            DateTime.now().difference(_businessDate(item)).inDays <= 7)
        .length;
    final completed = deliveries
        .where((item) => _businessStatusGroup(item) == 'completed')
        .length;
    final onTime = completed == 0 ? '0%' : '100%';
    final vanguard = deliveries.where(_businessIsVanguard).length;
    final stats = [
      (
        'Roth balance',
        '${_num(account['rothBalance']).toStringAsFixed(0)} Roth',
        'Not withdrawable',
        Icons.credit_score
      ),
      (
        'Active jobs this week',
        '$week',
        '$active active now',
        Icons.route_outlined
      ),
      (
        'On-time delivery rate',
        onTime,
        completed == 0 ? 'No completed jobs yet' : 'Completed jobs',
        Icons.speed_outlined
      ),
      (
        'Jobs under Vanguard cover',
        '$vanguard',
        'Sensitive items',
        Icons.shield_outlined
      )
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth < 640
          ? 1
          : constraints.maxWidth < 980
              ? 2
              : 4;
      return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: cols == 1 ? 3.5 : 1.65,
          children: stats
              .map((stat) => _BusinessStatCard(
                  label: stat.$1, value: stat.$2, note: stat.$3, icon: stat.$4))
              .toList());
    });
  }
}

class _BusinessInvoiceCard extends StatelessWidget {
  final Map<String, dynamic> account;
  final List<Map<String, dynamic>> deliveries;
  const _BusinessInvoiceCard({
    this.account = const {},
    this.deliveries = const [],
  });
  @override
  Widget build(BuildContext context) {
    final invoices = _businessInvoices(account);
    final outstanding = invoices.fold<double>(0, (runningTotal, item) {
      if (!_businessInvoiceIsPayable(item)) {
        return runningTotal;
      }
      return runningTotal + _num(item['balanceDue'] ?? item['total']);
    });
    final nextDue = _businessNextInvoiceDue(invoices);
    final overdue = nextDue != null && nextDue.isBefore(DateTime.now());
    final dueSoon = nextDue != null &&
        !overdue &&
        nextDue.difference(DateTime.now()).inDays <= 7;
    final borderColor = overdue
        ? Colors.redAccent.withValues(alpha: 0.42)
        : dueSoon
            ? Colors.amberAccent.withValues(alpha: 0.34)
            : Colors.white.withValues(alpha: 0.12);
    return _BusinessGlass(
        borderColor: borderColor,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _BusinessPanelHeader(
              title: 'Outstanding invoice',
              subtitle: 'Current business activity'),
          const SizedBox(height: 16),
          Text(
              outstanding <= 0 ? '£0.00' : '£${outstanding.toStringAsFixed(2)}',
              style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white, fontSize: 42, height: 1)),
          const SizedBox(height: 8),
          Text(
              outstanding <= 0
                  ? 'No payment due. Your invoice history remains available.'
                  : overdue
                      ? 'Invoice overdue. Open invoicing to pay by card or eligible Business Roth.'
                      : dueSoon
                          ? 'Invoice due within 7 days. Card and eligible Roth payments are available.'
                          : 'Card and eligible Business Roth payments are available.',
              style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w600,
                  height: 1.35)),
          const SizedBox(height: 16),
          Text(
              outstanding > 0
                  ? 'Choose an invoice below to pay securely.'
                  : 'Your invoice history is shown below.',
              style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800))
        ]));
  }
}

class _BusinessActivityTable extends StatelessWidget {
  final List<Map<String, dynamic>> deliveries;
  final bool showActions;
  final bool canRebook;
  final VoidCallback? onRebook;
  const _BusinessActivityTable({
    this.deliveries = const [],
    this.showActions = false,
    this.canRebook = false,
    this.onRebook,
  });
  @override
  Widget build(BuildContext context) {
    final rows = deliveries.take(12).toList();
    return _BusinessGlass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _BusinessPanelHeader(
          title: 'Recent activity',
          subtitle: 'Business deliveries and ecosystem actions'),
      const SizedBox(height: 12),
      if (rows.isEmpty)
        const _BusinessEmptyState('No business activity yet.')
      else
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
                headingTextStyle: GoogleFonts.jetBrainsMono(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 11,
                    fontWeight: FontWeight.w800),
                dataTextStyle: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w700),
                columns: [
                  DataColumn(label: Text('Job ID')),
                  DataColumn(label: Text('Pillar')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Amount')),
                  DataColumn(label: Text('Time')),
                  if (showActions) DataColumn(label: Text('Actions'))
                ],
                rows: rows
                    .map((row) => DataRow(cells: [
                          DataCell(Text(
                              '${row['trackingReference'] ?? row['id'] ?? 'Delivery'}')),
                          DataCell(Text(_businessPillar(row))),
                          DataCell(_BusinessBadge(
                              '${row['status'] ?? 'pending'}'.toUpperCase())),
                          DataCell(Text(
                              '£${_businessAmount(row).toStringAsFixed(2)}')),
                          DataCell(
                              Text(_businessDateLabel(_businessDate(row)))),
                          if (showActions)
                            DataCell(Wrap(spacing: 6, children: [
                              TextButton(
                                  onPressed: () => _showBusinessDeliveryDetails(
                                      context, row),
                                  child: const Text('Details')),
                              TextButton(
                                  onPressed: () => _openBusinessTracking(row),
                                  child: const Text('Track')),
                              TextButton(
                                  onPressed: canRebook ? onRebook : null,
                                  child: const Text('Rebook')),
                            ]))
                        ]))
                    .toList()))
    ]));
  }
}

class _BusinessInvoicePage extends StatelessWidget {
  final Map<String, dynamic> account;
  final List<Map<String, dynamic>> deliveries;
  final TextEditingController invoiceSearch;
  final bool canManage;
  final VoidCallback onBuyRoth;
  final void Function(Map<String, dynamic>, String) onPayInvoice;
  const _BusinessInvoicePage(
      {required this.account,
      required this.deliveries,
      required this.invoiceSearch,
      required this.canManage,
      required this.onBuyRoth,
      required this.onPayInvoice,
      required this.busy});
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final rothTransactions = _businessRothTransactions(account);
    final rothPurchases =
        ((account['recentBusinessRothPurchases'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
    final invoices = _businessInvoices(account);
    return Column(children: [
      _BusinessInvoiceCard(account: account, deliveries: deliveries),
      const SizedBox(height: 14),
      _BusinessGlass(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _BusinessPanelHeader(
            title: 'Business Roth wallet',
            subtitle:
                '${_num(account['rothBalance'] ?? account['businessRothBalance']).toStringAsFixed(2)} Roth available · not withdrawable'),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: busy ? null : onBuyRoth,
            icon: const Icon(Icons.add_card_outlined),
            label: Text(busy ? 'Starting secure checkout...' : 'Top Up Roth')),
        const SizedBox(height: 10),
        Text(
            'Roth can be used for eligible Circum business services but cannot be withdrawn.',
            style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (rothPurchases.isNotEmpty) ...[
          Text('Recent activity',
              style: GoogleFonts.inter(
                  color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...rothPurchases.take(4).map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                    child: Text(_businessRothActivityLabel(item),
                        style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w700))),
                Text('£${_num(item['amountGbp']).toStringAsFixed(2)}',
                    style: GoogleFonts.jetBrainsMono(
                        color: Colors.white, fontWeight: FontWeight.w800))
              ]))),
          const SizedBox(height: 8),
        ],
        if (rothTransactions.isEmpty)
          const _BusinessEmptyState(
              'Business Roth credits, gift card conversions and offsets will appear here when recorded.')
        else
          ...rothTransactions.take(8).map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                    child: Text(_businessRothActivityLabel(item),
                        style: GoogleFonts.inter(
                            color: Colors.white, fontWeight: FontWeight.w700))),
                Text(
                    '${item['direction'] == 'debit' ? '-' : '+'}${_num(item['amount']).toStringAsFixed(2)} Roth',
                    style: GoogleFonts.jetBrainsMono(
                        color: Colors.white, fontWeight: FontWeight.w800))
              ]))),
        const SizedBox(height: 8),
        Text(
            '1 Roth = £1 to use inside Circum. Roth is not withdrawable, not crypto, and can reduce eligible Business payments where enabled.',
            style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600))
      ])),
      const SizedBox(height: 14),
      _BusinessGlass(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _BusinessPanelHeader(
            title: 'Invoice history',
            subtitle: 'Issued Business invoices and payment history.'),
        const SizedBox(height: 12),
        _BusinessTextField(controller: invoiceSearch, label: 'Search invoices'),
        const SizedBox(height: 12),
        if (invoices.isEmpty)
          const _BusinessEmptyState('No outstanding invoices.')
        else
          ...invoices.take(8).map((invoice) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BusinessInvoicePaymentRow(
                  invoice: invoice,
                  rothBalance: _num(
                      account['rothBalance'] ?? account['businessRothBalance']),
                  busy: busy,
                  onPay: (method) => onPayInvoice(invoice, method),
                ),
              )),
      ]))
    ]);
  }
}

class _BusinessInvoicePaymentRow extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final double rothBalance;
  final bool busy;
  final ValueChanged<String> onPay;
  const _BusinessInvoicePaymentRow({
    required this.invoice,
    required this.rothBalance,
    required this.busy,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final status = '${invoice['status'] ?? 'draft'}'.toLowerCase();
    final balance = _num(invoice['balanceDue'] ?? invoice['total']);
    final payable = _businessInvoiceIsPayable(invoice);
    final label = _businessInvoiceCustomerStatus(invoice);
    final paidUsingRoth = _businessInvoicePaidWithRoth(invoice);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              _businessInvoiceDisplayTitle(invoice),
              style: GoogleFonts.inter(
                  color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ),
          Text('£${balance.toStringAsFixed(2)}',
              style: GoogleFonts.jetBrainsMono(
                  color: Colors.white, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 4),
        Text(label,
            style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        if (payable)
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: busy ? null : () => onPay('card'),
                icon: const Icon(Icons.credit_card_rounded),
                label: Text(busy
                    ? 'Starting secure checkout...'
                    : status == 'partially_paid'
                        ? 'Pay remaining balance'
                        : 'Pay invoice')),
            OutlinedButton.icon(
                onPressed:
                    !busy && rothBalance > 0 ? () => onPay('roth') : null,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Pay with Roth')),
            OutlinedButton.icon(
                onPressed: busy ? null : () => onPay('part'),
                icon: const Icon(Icons.call_split_rounded),
                label: const Text('Part Pay')),
          ])
        else
          Text(paidUsingRoth ? 'Paid using Roth' : label,
              style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _BusinessRothPurchaseRequest {
  final double amount;
  final String method;
  const _BusinessRothPurchaseRequest({
    required this.amount,
    required this.method,
  });
}

class _BusinessRothPurchaseDialog extends StatefulWidget {
  const _BusinessRothPurchaseDialog();

  @override
  State<_BusinessRothPurchaseDialog> createState() =>
      _BusinessRothPurchaseDialogState();
}

class _BusinessRothPurchaseDialogState
    extends State<_BusinessRothPurchaseDialog> {
  final _custom = TextEditingController();
  double _selected = 100;
  String _method = 'card';

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customAmount = double.tryParse(_custom.text.trim());
    final amount =
        customAmount != null && customAmount > 0 ? customAmount : _selected;
    final validAmount = amount > 0 && amount.isFinite;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(colors: [
              const Color(0xff3b82f6).withValues(alpha: 0.22),
              const Color(0xff101826).withValues(alpha: 0.94),
            ]),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xff3b82f6).withValues(alpha: 0.24),
                blurRadius: 42,
                offset: const Offset(0, 24),
              )
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Top Up Roth',
                style: GoogleFonts.dmSerifDisplay(
                    color: Colors.white, fontSize: 36, height: 1.02)),
            const SizedBox(height: 10),
            Text(
                'Roth can be used for eligible Circum business services but cannot be withdrawn.',
                style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.4,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [50, 100, 250, 500]
                    .map((value) => ChoiceChip(
                        selected: _selected == value && _custom.text.isEmpty,
                        label: Text('£$value'),
                        onSelected: (_) => setState(() {
                              _selected = value.toDouble();
                              _custom.clear();
                            })))
                    .toList()),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                  selected: _method == 'card',
                  label: const Text('Card payment'),
                  onSelected: (_) => setState(() => _method = 'card')),
              ChoiceChip(
                  selected: _method == 'manual',
                  label: const Text('Manual payment request'),
                  onSelected: (_) => setState(() => _method = 'manual')),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _custom,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(color: Colors.white),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Custom amount',
                labelStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.68)),
                prefixText: '£',
                prefixStyle: const TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 10),
            Text(
                validAmount
                    ? 'You will receive ${amount.toStringAsFixed(0)} Roth'
                    : 'Choose an amount to continue.',
                style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton(
                      onPressed: validAmount
                          ? () => Navigator.pop(
                              context,
                              _BusinessRothPurchaseRequest(
                                  amount: amount, method: _method))
                          : null,
                      child: Text(_method == 'card'
                          ? 'Continue to secure checkout'
                          : 'Submit manual request'))),
            ]),
          ])),
    );
  }
}

class _BusinessInvoicePartPaymentRequest {
  final double amount;
  final String method;
  const _BusinessInvoicePartPaymentRequest({
    required this.amount,
    required this.method,
  });
}

class _BusinessPartPaymentDialog extends StatefulWidget {
  final double maxAmount;
  final double rothBalance;
  const _BusinessPartPaymentDialog({
    required this.maxAmount,
    required this.rothBalance,
  });

  @override
  State<_BusinessPartPaymentDialog> createState() =>
      _BusinessPartPaymentDialogState();
}

class _BusinessPartPaymentDialogState
    extends State<_BusinessPartPaymentDialog> {
  final _amount = TextEditingController();
  String _method = 'card';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entered = double.tryParse(_amount.text.trim()) ?? 0;
    final value = entered.isFinite ? entered : 0;
    final validAmount = value > 0 && value <= widget.maxAmount;
    final rothAvailable = widget.rothBalance > 0;
    final canUseRoth =
        _method != 'roth' || (rothAvailable && value <= widget.rothBalance);
    return AlertDialog(
      backgroundColor: const Color(0xff101826),
      title: Text('Part Pay invoice',
          style: GoogleFonts.dmSerifDisplay(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            style: GoogleFonts.inter(color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Amount, max £${widget.maxAmount.toStringAsFixed(2)}',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              prefixText: '£',
              prefixStyle: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              selected: _method == 'card',
              label: const Text('Pay by Card'),
              onSelected: (_) => setState(() => _method = 'card'),
            ),
            ChoiceChip(
              selected: _method == 'roth',
              label: const Text('Pay with Roth'),
              onSelected: rothAvailable
                  ? (_) => setState(() => _method = 'roth')
                  : null,
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            _method == 'roth' && !canUseRoth
                ? 'Your Roth balance is lower than this amount.'
                : 'Choose how much of the invoice balance to pay now.',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.68),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: validAmount && canUseRoth
                ? () => Navigator.pop(
                      context,
                      _BusinessInvoicePartPaymentRequest(
                        amount: value.toDouble(),
                        method: _method,
                      ),
                    )
                : null,
            child: const Text('Continue')),
      ],
    );
  }
}

class _BusinessMomentDialog extends StatefulWidget {
  const _BusinessMomentDialog();

  @override
  State<_BusinessMomentDialog> createState() => _BusinessMomentDialogState();
}

class _BusinessMomentDialogState extends State<_BusinessMomentDialog> {
  final _name = TextEditingController();
  final _relationship = TextEditingController();
  final _date = TextEditingController();
  var _type = 'Employee birthday';
  var _action = 'Send Gift';

  @override
  void dispose() {
    _name.dispose();
    _relationship.dispose();
    _date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parsedDate = DateTime.tryParse(_date.text.trim());
    final valid = _name.text.trim().isNotEmpty && parsedDate != null;
    const types = [
      'Birthday',
      'Wedding',
      'Engagement',
      'Anniversary',
      'New Baby',
      'Graduation',
      'Promotion',
      'Retirement',
      'New Home',
      'Thank You',
      'Congratulations',
      'Get Well Soon',
      'Sympathy / Condolence',
      'Welcome',
      'Farewell',
      'Religious Celebration',
      'Cultural Celebration',
      'Employee Birthday',
      'Employee Work Anniversary',
      'Client Birthday',
      'Client Anniversary',
      'Supplier Anniversary',
      'Investor Milestone',
      'Company Milestone',
      'Contract Renewal',
      'Partnership Anniversary',
      'Customer Appreciation',
      'Staff Recognition',
      'Health+ Reminder',
      'Delivery Reminder',
      'Custom Reminder',
    ];
    const actions = [
      'Send Gift',
      'Create Delivery',
      'Schedule Health+ Delivery',
      'Create Reminder',
      'Send Card',
      'Snooze',
    ];
    return AlertDialog(
      backgroundColor: const Color(0xff101826),
      title: Text('Add IRIS Moment',
          style: GoogleFonts.dmSerifDisplay(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Add a person, company date or reminder. IRIS will suggest the best Circum action when it becomes relevant.',
            style: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            style: GoogleFonts.inter(color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Person or company'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _relationship,
            style: GoogleFonts.inter(color: Colors.white),
            decoration:
                const InputDecoration(labelText: 'Relationship optional'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            dropdownColor: const Color(0xff101826),
            decoration: const InputDecoration(labelText: 'Moment type'),
            items: types
                .map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(type,
                          style: GoogleFonts.inter(color: Colors.white)),
                    ))
                .toList(growable: false),
            onChanged: (value) => setState(() => _type = value ?? _type),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _date,
            style: GoogleFonts.inter(color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Date',
              hintText: 'YYYY-MM-DD',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _action,
            dropdownColor: const Color(0xff101826),
            decoration: const InputDecoration(labelText: 'Preferred action'),
            items: actions
                .map((action) => DropdownMenuItem(
                      value: action,
                      child: Text(action,
                          style: GoogleFonts.inter(color: Colors.white)),
                    ))
                .toList(growable: false),
            onChanged: (value) => setState(() => _action = value ?? _action),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: valid
              ? () {
                  Navigator.pop(context, {
                    'momentId': const Uuid().v4(),
                    'name': _name.text.trim(),
                    'relationship': _relationship.text.trim(),
                    'type': _type,
                    'eventDate': Timestamp.fromDate(parsedDate),
                    'preferredAction': _action,
                    'status': 'upcoming',
                    'createdAt': Timestamp.now(),
                    'lastUpdated': Timestamp.now(),
                  });
                }
              : null,
          child: const Text('Add Moment'),
        ),
      ],
    );
  }
}

class _BusinessTeamPage extends StatelessWidget {
  final Map<String, dynamic> account;
  final bool canManage;
  final TextEditingController inviteEmail;
  final TextEditingController inviteName;
  final String inviteRole;
  final ValueChanged<String> onInviteRole;
  final VoidCallback onInviteMember;
  final void Function(Map<String, dynamic>, String) onUpdateMember;
  final ValueChanged<Map<String, dynamic>> onRemoveMember;
  final ValueChanged<Map<String, dynamic>> onCancelInvite;
  final ValueChanged<Map<String, dynamic>> onResendInvite;
  const _BusinessTeamPage(
      {required this.account,
      required this.canManage,
      required this.inviteEmail,
      required this.inviteName,
      required this.inviteRole,
      required this.onInviteRole,
      required this.onInviteMember,
      required this.onUpdateMember,
      required this.onRemoveMember,
      required this.onCancelInvite,
      required this.onResendInvite});
  @override
  Widget build(BuildContext context) {
    final members = _businessMembers(account);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _BusinessGlass(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _BusinessPanelHeader(
            title: 'Team & access',
            subtitle: 'Owner and Admin can manage access.'),
        const SizedBox(height: 12),
        if (members.isEmpty)
          const _BusinessEmptyState('No team members yet.')
        else
          ...members.map((member) => _BusinessMemberRow(
              member: member,
              canManage: canManage,
              onUpdateRole: (role) => onUpdateMember(member, role),
              onRemove: () => onRemoveMember(member),
              onCancelInvite: () => onCancelInvite(member),
              onResendInvite: () => onResendInvite(member)))
      ])),
      if (canManage) ...[
        const SizedBox(height: 14),
        _BusinessGlass(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _BusinessPanelHeader(
              title: 'Invite team member',
              subtitle: 'Create a pending invite by email.'),
          const SizedBox(height: 12),
          _BusinessTextField(controller: inviteEmail, label: 'Email'),
          _BusinessTextField(controller: inviteName, label: 'Name optional'),
          Wrap(
              spacing: 8,
              children: _businessRoles
                  .map((role) => ChoiceChip(
                      selected: inviteRole == role,
                      label: Text(_businessRoleLabel(role)),
                      onSelected: (_) => onInviteRole(role)))
                  .toList()),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: onInviteMember,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Invite member'))
        ]))
      ]
    ]);
  }
}

class _BusinessMemberRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool canManage;
  final ValueChanged<String> onUpdateRole;
  final VoidCallback onRemove;
  final VoidCallback onCancelInvite;
  final VoidCallback onResendInvite;
  const _BusinessMemberRow(
      {required this.member,
      required this.canManage,
      required this.onUpdateRole,
      required this.onRemove,
      required this.onCancelInvite,
      required this.onResendInvite});
  @override
  Widget build(BuildContext context) {
    final role = '${member['role'] ?? 'viewer'}';
    final invited = '${member['status'] ?? ''}' == 'invited';
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(
              child: Text(
                  '${member['name'] ?? member['email'] ?? 'Team member'}\n${member['email'] ?? ''} · ${invited ? 'Pending invite' : 'Active'}',
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1.35))),
          if (canManage)
            DropdownButton<String>(
                value: _businessRoles.contains(role) ? role : 'viewer',
                dropdownColor: const Color(0xff111827),
                style: const TextStyle(color: Colors.white),
                items: _businessRoles
                    .map((role) => DropdownMenuItem(
                        value: role, child: Text(_businessRoleLabel(role))))
                    .toList(),
                onChanged: (next) {
                  if (next != null) onUpdateRole(next);
                })
          else
            _BusinessBadge(_businessRoleLabel(role).toUpperCase()),
          if (canManage && invited)
            TextButton(onPressed: onResendInvite, child: const Text('Resend')),
          if (canManage && invited)
            TextButton(onPressed: onCancelInvite, child: const Text('Cancel')),
          if (canManage)
            IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.white70))
        ]));
  }
}

class _BusinessMobileTabs extends StatelessWidget {
  final _BusinessPortalTab selectedTab;
  final ValueChanged<_BusinessPortalTab> onSelectTab;
  final String role;

  const _BusinessMobileTabs({
    required this.selectedTab,
    required this.onSelectTab,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = <(_BusinessPortalTab, String)>[
      (_BusinessPortalTab.overview, 'Overview'),
      (_BusinessPortalTab.deliveries, 'Deliveries'),
      (_BusinessPortalTab.invoicing, 'Invoices'),
      (_BusinessPortalTab.team, 'Team'),
      (_BusinessPortalTab.healthPlus, 'Health+'),
      (_BusinessPortalTab.gifts, 'Gifts'),
      (_BusinessPortalTab.vanguard, 'Vanguard'),
      (_BusinessPortalTab.analytics, 'Analytics'),
      (_BusinessPortalTab.settings, 'Settings'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs
            .map(
              (tab) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: selectedTab == tab.$1,
                  label: Text(tab.$2),
                  selectedColor:
                      const Color(0xff3b82f6).withValues(alpha: 0.20),
                  side: BorderSide(
                    color: selectedTab == tab.$1
                        ? const Color(0xff3b82f6).withValues(alpha: 0.68)
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                  onSelected: (_) => onSelectTab(tab.$1),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _BusinessDeliveriesPage extends StatelessWidget {
  final List<Map<String, dynamic>> deliveries;
  final bool canOperate;
  final VoidCallback onBookDelivery;
  const _BusinessDeliveriesPage(
      {required this.deliveries,
      required this.canOperate,
      required this.onBookDelivery});
  @override
  Widget build(BuildContext context) {
    final active = deliveries
        .where((item) => _businessStatusGroup(item) == 'active')
        .toList();
    final scheduled = deliveries
        .where((item) => _businessStatusGroup(item) == 'scheduled')
        .toList();
    final completed = deliveries
        .where((item) => _businessStatusGroup(item) == 'completed')
        .toList();
    final cancelled = deliveries
        .where((item) => _businessStatusGroup(item) == 'cancelled')
        .toList();
    return Column(children: [
      _BusinessSegmentCounts(items: [
        ('Active', active.length),
        ('Scheduled', scheduled.length),
        ('Completed', completed.length),
        ('Cancelled', cancelled.length)
      ]),
      const SizedBox(height: 14),
      _BusinessActivityTable(
          deliveries: deliveries,
          showActions: true,
          canRebook: canOperate,
          onRebook: onBookDelivery),
      const SizedBox(height: 14),
      Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(
                onPressed: canOperate ? onBookDelivery : null,
                icon: const Icon(Icons.add_road),
                label: const Text('Book delivery')),
            OutlinedButton.icon(
                onPressed: deliveries.isEmpty
                    ? null
                    : () => _downloadBusinessDeliveriesCsv(deliveries),
                icon: const Icon(Icons.download),
                label: const Text('Export delivery history'))
          ]))
    ]);
  }
}

class _BusinessServicePage extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Map<String, dynamic>> rows;
  final bool canCreate;
  final VoidCallback onCreate;
  const _BusinessServicePage(
      {required this.title,
      required this.icon,
      required this.rows,
      required this.canCreate,
      required this.onCreate});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _BusinessGlass(
          child: Row(children: [
        Icon(icon, color: const Color(0xff3b82f6), size: 32),
        const SizedBox(width: 12),
        Expanded(
            child: _BusinessPanelHeader(
                title: title,
                subtitle: 'Connected to the same Circum delivery ecosystem.')),
        FilledButton(
            onPressed: canCreate ? onCreate : null,
            child: const Text('Create request'))
      ])),
      const SizedBox(height: 14),
      _BusinessActivityTable(deliveries: rows, showActions: true)
    ]);
  }
}

class _BusinessAnalyticsPage extends StatelessWidget {
  final List<Map<String, dynamic>> deliveries;
  final Map<String, dynamic> account;
  const _BusinessAnalyticsPage(
      {required this.deliveries, required this.account});
  @override
  Widget build(BuildContext context) {
    final spend = deliveries.fold<double>(
        0, (runningTotal, item) => runningTotal + _businessAmount(item));
    final avg = deliveries.isEmpty ? 0 : spend / deliveries.length;
    final topRoutes = <String, int>{};
    for (final item in deliveries) {
      final route =
          '${item['pickupAddress'] ?? 'Pickup'} → ${item['dropoffAddress'] ?? 'Drop-off'}';
      topRoutes[route] = (topRoutes[route] ?? 0) + 1;
    }
    return Column(children: [
      _BusinessStatsGrid(deliveries: deliveries, account: account),
      const SizedBox(height: 14),
      _BusinessGlass(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _BusinessPanelHeader(
            title: 'Spend',
            subtitle: 'Average delivery cost £${avg.toStringAsFixed(2)}'),
        const SizedBox(height: 12),
        Text('Total business spend: £${spend.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        if (topRoutes.isEmpty)
          const _BusinessEmptyState(
              'Top routes will appear after business bookings.')
        else
          ...topRoutes.entries.take(5).map((item) => Text(
              '${item.key} · ${item.value}',
              style: GoogleFonts.inter(
                  color: Colors.white, fontWeight: FontWeight.w700)))
      ]))
    ]);
  }
}

class _BusinessSettingsPage extends StatelessWidget {
  final Map<String, dynamic> account;
  final bool canManage;
  final TextEditingController businessName;
  final TextEditingController contactName;
  final TextEditingController phone;
  final TextEditingController businessAddress;
  final TextEditingController companyNumber;
  final TextEditingController billingEmail;
  final TextEditingController defaultPickupAddress;
  final VoidCallback onSaveProfile;
  final VoidCallback onSignOut;
  const _BusinessSettingsPage(
      {required this.account,
      required this.canManage,
      required this.businessName,
      required this.contactName,
      required this.phone,
      required this.businessAddress,
      required this.companyNumber,
      required this.billingEmail,
      required this.defaultPickupAddress,
      required this.onSaveProfile,
      required this.onSignOut});
  @override
  Widget build(BuildContext context) {
    businessName.text = businessName.text.isEmpty
        ? '${account['businessName'] ?? ''}'
        : businessName.text;
    contactName.text = contactName.text.isEmpty
        ? '${account['contactName'] ?? ''}'
        : contactName.text;
    phone.text = phone.text.isEmpty ? '${account['phone'] ?? ''}' : phone.text;
    businessAddress.text = businessAddress.text.isEmpty
        ? '${account['businessAddress'] ?? ''}'
        : businessAddress.text;
    companyNumber.text = companyNumber.text.isEmpty
        ? '${account['companyNumber'] ?? ''}'
        : companyNumber.text;
    billingEmail.text = billingEmail.text.isEmpty
        ? '${account['billingEmail'] ?? ''}'
        : billingEmail.text;
    final pickups = ((account['defaultPickupAddresses'] as List?) ?? const [])
        .map((item) => '$item')
        .toList();
    defaultPickupAddress.text =
        defaultPickupAddress.text.isEmpty && pickups.isNotEmpty
            ? pickups.first
            : defaultPickupAddress.text;
    return _BusinessGlass(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _BusinessPanelHeader(
          title: 'Business profile',
          subtitle: 'Editable account details and billing contact.'),
      const SizedBox(height: 12),
      _BusinessTextField(
          controller: businessName, label: 'Business name', enabled: canManage),
      _BusinessTextField(
          controller: contactName, label: 'Contact name', enabled: canManage),
      _BusinessTextField(controller: phone, label: 'Phone', enabled: canManage),
      if (canManage)
        _AddressField(
          colors: const _CircumColors(true),
          icon: Icons.business_outlined,
          label: 'Business address',
          controller: businessAddress,
          glassStyle: true,
          onSelected: (address) =>
              businessAddress.text = address.displayAddress,
        )
      else
        _BusinessTextField(
            controller: businessAddress,
            label: 'Business address',
            enabled: false),
      const SizedBox(height: 10),
      _BusinessTextField(
          controller: companyNumber,
          label: 'VAT / company number optional',
          enabled: canManage),
      _BusinessTextField(
          controller: billingEmail, label: 'Billing email', enabled: canManage),
      if (canManage)
        _AddressField(
          colors: const _CircumColors(true),
          icon: Icons.radio_button_checked,
          label: 'Default pickup address',
          controller: defaultPickupAddress,
          glassStyle: true,
          onSelected: (address) =>
              defaultPickupAddress.text = address.displayAddress,
        )
      else
        _BusinessTextField(
            controller: defaultPickupAddress,
            label: 'Default pickup address',
            enabled: false),
      const SizedBox(height: 10),
      const SizedBox(height: 12),
      Wrap(spacing: 10, children: [
        FilledButton.icon(
            onPressed: canManage ? onSaveProfile : null,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save profile')),
        OutlinedButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'))
      ])
    ]));
  }
}

class _BusinessSegmentCounts extends StatelessWidget {
  final List<(String, int)> items;
  const _BusinessSegmentCounts({required this.items});
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final cols = constraints.maxWidth < 680 ? 2 : 4;
        return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.4,
            children: items
                .map((item) => _BusinessGlass(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(item.$1,
                              style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.64),
                                  fontWeight: FontWeight.w700)),
                          Text('${item.$2}',
                              style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900))
                        ])))
                .toList());
      });
}

class _BusinessTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final bool enabled;
  const _BusinessTextField(
      {required this.controller,
      required this.label,
      this.obscure = false,
      this.enabled = true});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
              labelText: label,
              labelStyle:
                  TextStyle(color: Colors.white.withValues(alpha: 0.58)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.12))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12))))));
}

class _BusinessEmptyState extends StatelessWidget {
  final String text;
  const _BusinessEmptyState(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.inter(
          color: Colors.white.withValues(alpha: 0.64),
          fontWeight: FontWeight.w700,
          height: 1.4));
}

class _BusinessStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final IconData icon;
  const _BusinessStatCard(
      {required this.label,
      required this.value,
      required this.note,
      required this.icon});
  @override
  Widget build(BuildContext context) => _BusinessGlass(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: const Color(0xff3b82f6).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(15),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.10))),
            child: Icon(icon, color: const Color(0xff3b82f6), size: 21)),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                      color: Colors.white.withValues(alpha: 0.52),
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(value,
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
              Text(note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                      fontWeight: FontWeight.w600))
            ]))
      ]));
}

class _BusinessGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  const _BusinessGlass({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderColor,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
              width: double.infinity,
              padding: padding,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.065),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color:
                          borderColor ?? Colors.white.withValues(alpha: 0.12)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 36,
                        offset: const Offset(0, 18))
                  ]),
              child: child)));
}

class _BusinessPanelHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _BusinessPanelHeader({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.58),
                fontWeight: FontWeight.w600))
      ]);
}

class _BusinessMiniCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _BusinessMiniCard(
      {required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) => _BusinessGlass(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Icon(icon, color: const Color(0xff3b82f6), size: 24),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(title,
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600))
            ]))
      ]));
}

class _BusinessNavGroup extends StatelessWidget {
  final String title;
  final List<(IconData, String, _BusinessPortalTab)> items;
  final _BusinessPortalTab selectedTab;
  final ValueChanged<_BusinessPortalTab> onSelectTab;
  const _BusinessNavGroup(
      {required this.title,
      required this.items,
      required this.selectedTab,
      required this.onSelectTab});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: GoogleFonts.jetBrainsMono(
                color: Colors.white.withValues(alpha: 0.42),
                fontSize: 11,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 9),
        ...items.map((item) {
          final selected = item.$3 == selectedTab;
          return InkWell(
              onTap: () => onSelectTab(item.$3),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xff3b82f6).withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: selected
                              ? const Color(0xff3b82f6).withValues(alpha: 0.68)
                              : Colors.transparent)),
                  child: Row(children: [
                    Icon(item.$1,
                        color: Colors.white.withValues(alpha: 0.72), size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(item.$2,
                            style: GoogleFonts.inter(
                                color: Colors.white
                                    .withValues(alpha: selected ? 1 : 0.68),
                                fontWeight: FontWeight.w800)))
                  ])));
        })
      ]);
}

class _BusinessTierCard extends StatelessWidget {
  final List<Map<String, dynamic>> deliveries;
  const _BusinessTierCard({required this.deliveries});
  @override
  Widget build(BuildContext context) => _BusinessGlass(
      padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _BusinessBadge('BUSINESS — GROWTH'),
        const SizedBox(height: 12),
        ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
                minHeight: 8,
                value: (deliveries.length / 100).clamp(0, 1),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation(Color(0xff3b82f6)))),
        const SizedBox(height: 8),
        Text('${deliveries.length} / 100 monthly jobs to Scale tier',
            style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 12,
                fontWeight: FontWeight.w700))
      ]));
}

class _BusinessEyebrow extends StatelessWidget {
  final String text;
  const _BusinessEyebrow(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: GoogleFonts.jetBrainsMono(
          color: const Color(0xff3b82f6),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2));
}

class _BusinessBadge extends StatelessWidget {
  final String label;
  const _BusinessBadge(this.label);
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
      child: Text(label,
          style: GoogleFonts.jetBrainsMono(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 10,
              fontWeight: FontWeight.w800)));
}

class _BusinessGlow extends StatelessWidget {
  final double size;
  final Color color;
  const _BusinessGlow({required this.size, required this.color});
  @override
  Widget build(BuildContext context) => IgnorePointer(
      child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                color.withValues(alpha: 0.22),
                color.withValues(alpha: 0.05),
                Colors.transparent
              ]))));
}

const _businessRoles = ['owner', 'admin', 'operations', 'finance', 'viewer'];

String _businessRole(Map<String, dynamic> account, User user) {
  final uid = user.uid;
  final email = (user.email ?? '').toLowerCase();
  for (final member in _businessMembers(account)) {
    final id = '${member['userId'] ?? ''}'.toLowerCase();
    final memberEmail = '${member['email'] ?? ''}'.toLowerCase();
    if (id == uid.toLowerCase() || id == email || memberEmail == email) {
      return '${member['role'] ?? 'viewer'}';
    }
  }
  return '${account['createdByUserId'] ?? ''}' == uid ? 'owner' : 'viewer';
}

bool _businessCanManage(String role) => role == 'owner' || role == 'admin';

bool _businessCanOperate(String role) =>
    role == 'owner' || role == 'admin' || role == 'operations';

bool _businessCanFinance(String role) =>
    role == 'owner' || role == 'admin' || role == 'finance';

String _businessRoleLabel(String role) => switch (role) {
      'owner' => 'Owner',
      'admin' => 'Admin',
      'operations' => 'Operations',
      'finance' => 'Finance',
      _ => 'Viewer'
    };

List<Map<String, dynamic>> _businessMembers(Map<String, dynamic> account) =>
    ((account['teamMembers'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

List<Map<String, dynamic>> _businessRothTransactions(
        Map<String, dynamic> account) =>
    ((account['rothTransactions'] ??
                account['businessRothTransactions'] ??
                account['recentBusinessRothTransactions'] ??
                account['rothLedger']) as List? ??
            const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

List<Map<String, dynamic>> _businessInvoices(Map<String, dynamic> account) =>
    _dedupeBusinessInvoices(
        ((account['recentBusinessInvoices'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false));

List<Map<String, dynamic>> _dedupeBusinessInvoices(
  List<Map<String, dynamic>> invoices,
) {
  final byId = <String, Map<String, dynamic>>{};
  for (final invoice in invoices) {
    final id =
        '${invoice['invoiceId'] ?? invoice['id'] ?? invoice['invoiceNumber'] ?? ''}';
    if (id.isEmpty) continue;
    final existing = byId[id];
    if (existing == null ||
        _businessInvoiceRank(invoice) >= _businessInvoiceRank(existing)) {
      byId[id] = invoice;
    }
  }
  return byId.values.toList(growable: false);
}

int _businessInvoiceRank(Map<String, dynamic> invoice) {
  final status = _businessInvoiceStatus(invoice);
  final statusRank = switch (status) {
    'paid' || 'paid_manually' || 'paid_with_roth' => 6,
    'partially_paid' => 5,
    'issued' || 'unpaid' => 4,
    'draft' => 3,
    'cancelled' || 'canceled' => 2,
    'void' || 'voided' => 1,
    _ => 0,
  };
  return statusRank * 10000000000000 +
      _businessDate(invoice).millisecondsSinceEpoch;
}

String _businessInvoiceStatus(Map<String, dynamic> invoice) =>
    '${invoice['status'] ?? 'draft'}'.toLowerCase().trim();

bool _businessInvoicePaidWithRoth(Map<String, dynamic> invoice) {
  final method = '${invoice['paymentMethod'] ?? invoice['method'] ?? ''}'
      .toLowerCase()
      .trim();
  return _businessInvoiceStatus(invoice) == 'paid_with_roth' ||
      method == 'roth' ||
      method == 'roth_card';
}

bool _businessInvoiceIsPayable(Map<String, dynamic> invoice) {
  final status = _businessInvoiceStatus(invoice);
  final balance = _num(invoice['balanceDue'] ?? invoice['total']);
  return balance > 0 &&
      const {'issued', 'unpaid', 'partially_paid'}.contains(status);
}

String _businessInvoiceCustomerStatus(Map<String, dynamic> invoice) {
  final status = _businessInvoiceStatus(invoice);
  if (_businessInvoicePaidWithRoth(invoice) &&
      const {'paid', 'paid_manually', 'paid_with_roth'}.contains(status)) {
    return 'Paid using Roth';
  }
  return switch (status) {
    'draft' => 'Preparing invoice',
    'issued' || 'unpaid' => 'Ready for payment',
    'partially_paid' => 'Partially paid',
    'paid' || 'paid_manually' => 'Paid',
    'cancelled' || 'canceled' => 'Cancelled',
    'void' || 'voided' => 'Void',
    _ => 'Ready for payment',
  };
}

String _businessInvoiceDisplayTitle(Map<String, dynamic> invoice) {
  final reference =
      '${invoice['invoiceNumber'] ?? invoice['invoiceId'] ?? 'Invoice'}';
  final match = RegExp(r'(\d{3,})$').firstMatch(reference);
  if (match != null) return 'Invoice #${match.group(1)}';
  return reference.startsWith('Invoice') ? reference : 'Invoice';
}

String _businessRothActivityLabel(Map<String, dynamic> item) {
  final raw = '${item['source'] ?? item['type'] ?? item['status'] ?? ''}'
      .toLowerCase()
      .trim();
  final reason = '${item['reason'] ?? item['note'] ?? ''}'.toLowerCase();
  if (raw.contains('invoice_payment') || reason.contains('invoice')) {
    return reason.contains('part')
        ? 'Part payment made'
        : 'Invoice paid using Roth';
  }
  if (raw.contains('admin_credit')) return 'Issued by Circum';
  if (raw.contains('admin_debit')) return 'Issued by Circum';
  if (raw.contains('admin_adjustment')) return 'Issued by Circum';
  if (raw.contains('manual_credit')) return 'Issued by Circum';
  if (raw.contains('roth_purchase') || raw == 'paid') {
    return 'Roth top-up completed';
  }
  if (raw.contains('pending') || raw.contains('verification')) {
    return 'Waiting for payment confirmation';
  }
  if (raw.contains('cancel')) return 'Roth top-up cancelled';
  return 'Business Roth activity';
}

DateTime? _businessNextInvoiceDue(List<Map<String, dynamic>> invoices) {
  final dueDates = invoices
      .where((item) {
        return _businessInvoiceIsPayable(item);
      })
      .map((item) => _businessDate({'dueDate': item['dueDate']}))
      .where((date) => date.millisecondsSinceEpoch != 0)
      .toList()
    ..sort();
  return dueDates.isEmpty ? null : dueDates.first;
}

DateTime _businessDate(Map<String, dynamic> item) {
  final raw = item['scheduledDateTime'] ??
      item['scheduledFor'] ??
      item['deliveryDateTime'] ??
      item['dueDate'] ??
      item['createdAt'] ??
      item['updatedAt'];
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

String _businessDateLabel(DateTime date) => date.millisecondsSinceEpoch == 0
    ? 'Not dated'
    : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

List<Map<String, dynamic>> _businessMoments(Map<String, dynamic> account) {
  final raw = ((account['irisMoments'] ??
          account['moments'] ??
          account['businessMoments']) as List?) ??
      const [];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false)
    ..sort((a, b) => _momentDate(a).compareTo(_momentDate(b)));
}

DateTime _momentDate(Map<String, dynamic> moment) {
  final raw = moment['eventDate'] ??
      moment['date'] ??
      moment['dueAt'] ??
      moment['reminderAt'] ??
      moment['createdAt'];
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  return DateTime.tryParse('$raw') ?? DateTime.fromMillisecondsSinceEpoch(0);
}

String _momentStatus(Map<String, dynamic> moment) =>
    '${moment['status'] ?? 'upcoming'}'.trim().toLowerCase();

String _momentName(Map<String, dynamic> moment) {
  final name =
      '${moment['name'] ?? moment['personName'] ?? moment['companyName'] ?? ''}'
          .trim();
  return name.isEmpty ? 'Important moment' : name;
}

String _momentTypeLabel(Map<String, dynamic> moment) {
  final type =
      '${moment['type'] ?? moment['eventType'] ?? 'Custom reminder'}'.trim();
  return type.isEmpty ? 'Custom reminder' : type;
}

String _momentDateLabel(Map<String, dynamic> moment) {
  final date = _momentDate(moment);
  if (date.millisecondsSinceEpoch == 0) return 'Date to confirm';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff > 1 && diff < 7) return 'In $diff days';
  return _businessDateLabel(date);
}

String _momentBucket(Map<String, dynamic> moment) {
  final date = _momentDate(moment);
  if (date.millisecondsSinceEpoch == 0) return 'later';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'today';
  if (diff > 0 && diff < 7) return 'week';
  if (diff >= 7 && diff < 31) return 'month';
  return 'later';
}

(String, String) _momentRecommendation(
  Map<String, dynamic> moment,
  List<Map<String, dynamic>> allMoments,
) {
  final name = _momentName(moment);
  final service = _momentRecommendedService(moment);
  if (_momentIsHealth(moment)) {
    return (
      '$name has a Health+ reminder ${_momentCountdown(moment).toLowerCase()}.',
      'Launch a Health+ Delivery request. ${_momentWhy(moment, allMoments)}.'
    );
  }
  if (_momentIsDelivery(moment)) {
    return (
      '$name has a delivery reminder ${_momentCountdown(moment).toLowerCase()}.',
      'Launch a Delivery request. ${_momentWhy(moment, allMoments)}.'
    );
  }
  if (_momentIsGiftOpportunity(moment)) {
    return (
      '$name has an important relationship moment ${_momentCountdown(moment).toLowerCase()}.',
      '$service ${_momentWhy(moment, allMoments)}.'
    );
  }
  return (
    '$name has a saved moment ${_momentCountdown(moment).toLowerCase()}.',
    '$service ${_momentWhy(moment, allMoments)}.'
  );
}

String _businessTimeGreeting() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  if (hour >= 17 && hour < 22) return 'Good evening';
  return 'Working late';
}

String _momentCountdown(Map<String, dynamic> moment) =>
    _momentDateLabel(moment).toLowerCase();

bool _momentIsHealth(Map<String, dynamic> moment) {
  final text = '${_momentTypeLabel(moment)} ${moment['preferredAction'] ?? ''}'
      .toLowerCase();
  return text.contains('health') ||
      text.contains('medication') ||
      text.contains('prescription');
}

bool _momentIsDelivery(Map<String, dynamic> moment) {
  final text = '${_momentTypeLabel(moment)} ${moment['preferredAction'] ?? ''}'
      .toLowerCase();
  return text.contains('delivery') && !_momentIsHealth(moment);
}

bool _momentIsGiftOpportunity(Map<String, dynamic> moment) {
  if (_momentIsHealth(moment) || _momentIsDelivery(moment)) return false;
  final text = '${_momentTypeLabel(moment)} ${moment['preferredAction'] ?? ''}'
      .toLowerCase();
  const giftSignals = [
    'birthday',
    'wedding',
    'engagement',
    'anniversary',
    'baby',
    'graduation',
    'promotion',
    'retirement',
    'home',
    'thank',
    'congratulations',
    'get well',
    'sympathy',
    'condolence',
    'welcome',
    'farewell',
    'celebration',
    'milestone',
    'appreciation',
    'recognition',
    'gift',
    'card',
  ];
  return giftSignals.any(text.contains);
}

String _momentRecommendedService(Map<String, dynamic> moment) {
  final type = _momentTypeLabel(moment);
  if (_momentIsHealth(moment)) return 'Launch a Health+ Delivery request.';
  if (_momentIsDelivery(moment)) return 'Launch a Delivery request.';
  if (_momentIsGiftOpportunity(moment)) {
    final cleanType =
        type.replaceAll(RegExp(r'\s+'), ' ').replaceAll('/', '').trim();
    return 'Launch a $cleanType Gift request via the Circum Gift Portal.';
  }
  return 'Create a reminder and choose the next Circum action.';
}

String _momentWhy(
  Map<String, dynamic> moment,
  List<Map<String, dynamic>> allMoments,
) {
  final type = _momentTypeLabel(moment).toLowerCase();
  final name = _momentName(moment);
  final sameTypeCompleted = allMoments.any((item) =>
      _momentStatus(item) == 'completed' &&
      _momentTypeLabel(item).toLowerCase() == type);
  final acceptedBefore = allMoments.any((item) =>
      '${item['lastAction'] ?? item['completedAction'] ?? item['preferredAction'] ?? ''}'
          .trim()
          .isNotEmpty &&
      _momentStatus(item) == 'completed');
  if (_momentIsHealth(moment)) return 'Based on a saved Health+ schedule';
  if (_momentIsDelivery(moment)) {
    return 'Based on a user-created delivery reminder';
  }
  if (sameTypeCompleted) return 'Based on previous Circum activity';
  if (acceptedBefore) return 'Based on previous business behaviour';
  if (type.contains('policy')) return 'Based on company policy';
  if (type.contains('birthday')) return 'Upcoming birthday';
  if (type.contains('anniversary')) return 'Upcoming anniversary';
  if (type.contains('milestone')) return 'Company milestone';
  return 'User-created reminder for $name';
}

double _momentRecommendationConfidence(
  Map<String, dynamic> moment,
  List<Map<String, dynamic>> allMoments,
) {
  var score =
      _momentIsGiftOpportunity(moment) || _momentIsHealth(moment) ? 0.72 : 0.62;
  final type = _momentTypeLabel(moment).toLowerCase();
  final sameTypeCompleted = allMoments
      .where((item) =>
          _momentStatus(item) == 'completed' &&
          _momentTypeLabel(item).toLowerCase() == type)
      .length;
  final dismissals = allMoments
      .where((item) =>
          _momentTypeLabel(item).toLowerCase() == type &&
          {'dismissed', 'snoozed'}.contains(_momentStatus(item)))
      .length;
  score += (sameTypeCompleted * 0.06).clamp(0, 0.18);
  score -= (dismissals * 0.08).clamp(0, 0.24);
  if ('${moment['preferredAction'] ?? ''}'.trim().isNotEmpty) score += 0.04;
  if (_momentBucket(moment) == 'today') score += 0.05;
  return score.clamp(0.32, 0.94).toDouble();
}

List<Map<String, dynamic>> _relationshipHealthRows(
  List<Map<String, dynamic>> moments,
) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final moment in moments) {
    final name = _momentName(moment);
    grouped.putIfAbsent(name, () => []).add(moment);
  }
  final rows = <Map<String, dynamic>>[];
  for (final entry in grouped.entries) {
    final items = entry.value;
    final completed = items
        .where((item) => _momentStatus(item) == 'completed')
        .toList(growable: false)
      ..sort((a, b) => _momentDate(b).compareTo(_momentDate(a)));
    final upcoming = items
        .where((item) => _momentStatus(item) != 'completed')
        .toList(growable: false)
      ..sort((a, b) => _momentDate(a).compareTo(_momentDate(b)));
    final lastCompleted =
        completed.isEmpty ? null : _momentDate(completed.first);
    final daysSince = lastCompleted == null
        ? null
        : DateTime.now().difference(lastCompleted).inDays;
    final status = daysSince == null
        ? (upcoming.isEmpty ? 'Growing' : 'Strong')
        : daysSince > 300
            ? 'Needs Attention'
            : daysSince > 150
                ? 'Growing'
                : 'Strong';
    final detail = daysSince == null
        ? (upcoming.isEmpty
            ? 'No completed Circum activity recorded yet.'
            : 'Next moment: ${_momentTypeLabel(upcoming.first)} ${_momentDateLabel(upcoming.first).toLowerCase()}.')
        : 'Last appreciation action: $daysSince days ago.';
    final insight = status == 'Needs Attention'
        ? 'This relationship may benefit from renewed engagement.'
        : status == 'Growing'
            ? 'A thoughtful Circum action could strengthen this relationship.'
            : 'Recent activity suggests this relationship is being maintained.';
    rows.add({
      'name': entry.key,
      'status': status,
      'detail': detail,
      'insight': insight,
    });
  }
  rows.sort((a, b) {
    const priority = {'Needs Attention': 0, 'Growing': 1, 'Strong': 2};
    return (priority[a['status']] ?? 9).compareTo(priority[b['status']] ?? 9);
  });
  return rows;
}

double _num(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

double _businessAmount(Map<String, dynamic> item) =>
    _num(item['businessAmount'] ??
        item['amount'] ??
        item['pricePaid'] ??
        item['price'] ??
        item['total']);

bool _businessIsVanguard(Map<String, dynamic> item) =>
    item['vanguardEnabled'] == true ||
    '${item['serviceType'] ?? ''}'.toUpperCase() == 'VANGUARD' ||
    ((item['vanguardProtection'] as Map?)?['enabled'] == true);

String _businessPillar(Map<String, dynamic> item) {
  final service =
      '${item['serviceType'] ?? item['sourceModule'] ?? ''}'.toUpperCase();
  if (service.contains('HEALTH')) return 'Health+';
  if (service.contains('GIFT')) return 'Gifts';
  if (_businessIsVanguard(item)) return 'Vanguard';
  return 'Delivery';
}

String _businessStatusGroup(Map<String, dynamic> item) {
  final status = '${item['status'] ?? ''}'.toLowerCase();
  if (status.contains('cancel') || status.contains('failed')) {
    return 'cancelled';
  }
  if (status.contains('complete') || status.contains('deliver')) {
    return 'completed';
  }
  if (status.contains('sched')) return 'scheduled';
  return 'active';
}

String _tabEyebrow(_BusinessPortalTab tab) => switch (tab) {
      _BusinessPortalTab.overview => 'Business · Account overview',
      _BusinessPortalTab.invoicing => 'Business · Invoicing',
      _BusinessPortalTab.team => 'Business · Team & access',
      _BusinessPortalTab.deliveries => 'Business · Deliveries',
      _BusinessPortalTab.healthPlus => 'Business · Health+',
      _BusinessPortalTab.gifts => 'Business · Gifts',
      _BusinessPortalTab.vanguard => 'Business · Vanguard',
      _BusinessPortalTab.analytics => 'Business · Analytics',
      _BusinessPortalTab.settings => 'Business · Settings'
    };

String _tabTitle(_BusinessPortalTab tab, Map<String, dynamic> account) =>
    switch (tab) {
      _BusinessPortalTab.overview => _businessGreeting(account),
      _BusinessPortalTab.invoicing => 'Invoices and Roth offsets.',
      _BusinessPortalTab.team => 'Team access.',
      _BusinessPortalTab.deliveries => 'Business deliveries.',
      _BusinessPortalTab.healthPlus => 'Health+ operations.',
      _BusinessPortalTab.gifts => 'Corporate gifts.',
      _BusinessPortalTab.vanguard => 'Vanguard coverage.',
      _BusinessPortalTab.analytics => 'Business analytics.',
      _BusinessPortalTab.settings => 'Business profile.'
    };

String _businessGreeting(Map<String, dynamic> account, [DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  final greeting = hour >= 5 && hour < 12
      ? 'Good morning'
      : hour >= 12 && hour < 17
          ? 'Good afternoon'
          : hour >= 17 && hour < 22
              ? 'Good evening'
              : 'Working late';
  final name = '${account['businessName'] ?? ''}'.trim();
  return name.isEmpty ? '$greeting.' : '$greeting, $name.';
}

String _tabSubtitle(_BusinessPortalTab tab) => switch (tab) {
      _BusinessPortalTab.overview =>
        'Your command centre for deliveries, invoices, team access, Health+, Gifts, Vanguard and IRIS insights.',
      _BusinessPortalTab.invoicing =>
        'View invoice history, delivery breakdowns and Roth credits where available.',
      _BusinessPortalTab.team =>
        'Invite, remove and permission team members by role.',
      _BusinessPortalTab.deliveries =>
        'Book, track, rebook and export business movement history.',
      _BusinessPortalTab.healthPlus =>
        'Create and monitor Health+ business requests with Vanguard included.',
      _BusinessPortalTab.gifts =>
        'Create and monitor corporate gift requests without exposing surprise details.',
      _BusinessPortalTab.vanguard =>
        'Review sensitive deliveries and Vanguard-covered jobs.',
      _BusinessPortalTab.analytics =>
        'Real delivery and spend patterns appear here as business activity grows.',
      _BusinessPortalTab.settings =>
        'Manage account details, billing email and default pickup address.'
    };

List<Map<String, dynamic>> _healthRows(List<Map<String, dynamic>> rows) =>
    rows.where((item) => _businessPillar(item) == 'Health+').toList();

List<Map<String, dynamic>> _giftRows(List<Map<String, dynamic>> rows) =>
    rows.where((item) => _businessPillar(item) == 'Gifts').toList();

List<Map<String, dynamic>> _vanguardRows(List<Map<String, dynamic>> rows) =>
    rows.where(_businessIsVanguard).toList();

void _openBusinessTracking(Map<String, dynamic> delivery) {
  final id =
      '${delivery['id'] ?? delivery['deliveryId'] ?? delivery['requestId'] ?? ''}';
  final uri = Uri.base
      .resolve(id.isEmpty ? '/?app=business' : '/?app=sender&deliveryId=$id');
  unawaited(launchUrl(uri, webOnlyWindowName: '_self'));
}

void _downloadBusinessDeliveriesCsv(List<Map<String, dynamic>> deliveries) {
  final rows = [
    ['Job ID', 'Pillar', 'Status', 'Amount', 'Date'],
    ...deliveries.map((item) => [
          '${item['trackingReference'] ?? item['id'] ?? item['requestId'] ?? ''}',
          _businessPillar(item),
          '${item['status'] ?? 'pending'}',
          _businessAmount(item).toStringAsFixed(2),
          _businessDateLabel(_businessDate(item)),
        ])
  ];
  final csv = rows
      .map((row) =>
          row.map((cell) => '"${cell.replaceAll('"', '""')}"').join(','))
      .join('\n');
  final blob = html.Blob([csv], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = 'circum-business-deliveries.csv'
    ..click();
  html.Url.revokeObjectUrl(url);
}

void _showBusinessDeliveryDetails(
    BuildContext context, Map<String, dynamic> delivery) {
  final rows = <(String, String)>[
    (
      'Reference',
      '${delivery['trackingReference'] ?? delivery['id'] ?? delivery['requestId'] ?? 'Delivery'}'
    ),
    ('Pillar', _businessPillar(delivery)),
    ('Status', '${delivery['status'] ?? 'pending'}'),
    ('Amount', '£${_businessAmount(delivery).toStringAsFixed(2)}'),
    ('Pickup', '${delivery['pickupAddress'] ?? 'Not recorded'}'),
    ('Drop-off', '${delivery['dropoffAddress'] ?? 'Not recorded'}'),
    ('Vanguard', _businessIsVanguard(delivery) ? 'Included' : 'Not included'),
    ('Date', _businessDateLabel(_businessDate(delivery))),
  ];
  showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            backgroundColor: const Color(0xff0b1220),
            title: const Text('Business delivery details'),
            content: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: rows
                        .map((row) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text('${row.$1}: ${row.$2}'),
                            ))
                        .toList())),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close')),
              FilledButton(
                  onPressed: () => _openBusinessTracking(delivery),
                  child: const Text('View tracking')),
            ],
          ));
}

class _HealthPlusLandingBand extends StatelessWidget {
  final _CircumColors colors;
  final VoidCallback onHealthPlus;

  const _HealthPlusLandingBand({
    required this.colors,
    required this.onHealthPlus,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 820;
    return Container(
      width: double.infinity,
      color: const Color(0xff08111f),
      padding: const EdgeInsets.fromLTRB(22, 58, 22, 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Flex(
            direction: narrow ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: narrow ? 0 : 7,
                child: Column(
                  crossAxisAlignment: narrow
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    const _BusinessEyebrow('Health+'),
                    const SizedBox(height: 10),
                    Text(
                      'Prescription logistics with business-grade visibility.',
                      textAlign: narrow ? TextAlign.center : TextAlign.left,
                      style: GoogleFonts.dmSerifDisplay(
                        color: Colors.white,
                        fontSize: narrow ? 38 : 48,
                        height: 1.04,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Arrange one-off or recurring prescription pickups with sealed-package handling, reminders, and Vanguard-level care where it matters.',
                      textAlign: narrow ? TextAlign.center : TextAlign.left,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.72),
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onHealthPlus,
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text('Get started with Health+'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xff08111f),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 17,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: narrow ? 0 : 28, height: narrow ? 24 : 0),
              Expanded(
                flex: narrow ? 0 : 5,
                child: _BusinessGlass(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _BusinessPanelHeader(
                        title: 'Health+ operations',
                        subtitle: 'Pickup, reminders, custody timeline',
                      ),
                      const SizedBox(height: 16),
                      ...[
                        ('Prescription pickup', Icons.medication_outlined),
                        ('Recurring reminders', Icons.event_repeat_outlined),
                        ('Secure checkout', Icons.lock_outline),
                        ('Sealed packages only', Icons.inventory_2_outlined),
                      ].map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Icon(item.$2,
                                  color: const Color(0xff93c5fd), size: 20),
                              const SizedBox(width: 10),
                              Text(
                                item.$1,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

class _LandingFooter extends StatelessWidget {
  final _CircumColors colors;

  const _LandingFooter({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: _GlobalLegalFooter(colors: colors, showWordmark: true),
        ),
      ),
    );
  }
}

class _GlobalLegalFooter extends StatelessWidget {
  final _CircumColors colors;
  final bool showWordmark;

  const _GlobalLegalFooter({required this.colors, this.showWordmark = false});

  Future<void> _open(String path) async {
    await launchUrl(Uri.base.resolve(path), webOnlyWindowName: '_self');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            colors.adminAccent.withValues(alpha: 0.10),
            colors.adminGlow.withValues(alpha: 0.07),
            colors.field.withValues(alpha: 0.62),
          ],
        ),
        border: Border.all(color: colors.border.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: colors.adminGlow.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 28,
        runSpacing: 18,
        children: [
          if (showWordmark)
            Image.asset(
              'assets/images/circum_wordmark.png',
              width: 118,
              height: 28,
              fit: BoxFit.contain,
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Services',
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  TextButton(
                    onPressed: () => _open('/?app=sender'),
                    child: const Text('Deliveries'),
                  ),
                  TextButton(
                    onPressed: () => _open('/?app=health'),
                    child: const Text('Health+'),
                  ),
                  TextButton(
                    onPressed: () => _open('/?app=gifts'),
                    child: const Text('Gifts by Circum'),
                  ),
                  TextButton(
                    onPressed: () => _open('/business'),
                    child: const Text('Business'),
                  ),
                  TextButton(
                    onPressed: () => _open('/vanguard'),
                    child: const Text('Vanguard'),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Resources',
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  TextButton(
                    onPressed: () => _open('/terms'),
                    child: const Text('Terms of Service'),
                  ),
                  TextButton(
                    onPressed: () => _open('/privacy'),
                    child: const Text('Privacy Policy'),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Legal',
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '© 2026 Circum Technologies Ltd. All rights reserved.',
                style: TextStyle(color: colors.mutedText, height: 1.35),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VanguardExplainerPage extends StatelessWidget {
  final VoidCallback onHome;

  const _VanguardExplainerPage({super.key, required this.onHome});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xff3b82f6);
    const features = [
      (
        Icons.verified_user_outlined,
        'Trusted Rider Prioritisation',
        'Circum prioritises experienced and highly trusted riders during assignment. Customers do not choose riders.'
      ),
      (
        Icons.support_agent,
        'Priority support',
        'Vanguard deliveries receive priority support and dispute review.'
      ),
      (
        Icons.route_outlined,
        'Enhanced custody tracking',
        'Clearer delivery milestones create stronger visibility from assignment to delivery.'
      ),
    ];
    const timeline = [
      'Rider assigned',
      'Item collected',
      'In transit',
      'Delivery attempt',
      'Delivered',
    ];
    const useCases = [
      'Gifts and keepsakes',
      'Signed documents',
      'Passports and travel documents',
      'Electronics and valuable items',
      'Fragile items',
      'Sentimental items',
    ];
    const additions = [
      'Trusted Rider Prioritisation',
      'Priority support',
      'Enhanced custody tracking',
      'Priority dispute review',
      'Better handling for important items',
    ];
    const included = [
      'Health+',
      'Gifts by Circum',
      'Corporate Gifts',
      'Required high-value deliveries',
    ];
    Widget glass(Widget child,
        {EdgeInsets padding = const EdgeInsets.all(22)}) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white.withValues(alpha: 0.045),
          border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 36,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: child,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xff07090f),
      body: _VanguardPageBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 54),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 920),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: onHome,
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Image.asset(
                                'assets/images/circum_wordmark.png',
                                width: 124,
                                height: 30,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(height: 44),
                          Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 82,
                                  height: 82,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: blue.withValues(alpha: 0.10),
                                    border: Border.all(
                                        color: blue.withValues(alpha: 0.42)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xff8b5cf6)
                                            .withValues(alpha: 0.12),
                                        blurRadius: 32,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.shield_outlined,
                                      color: blue, size: 42),
                                ),
                                const SizedBox(height: 22),
                                Text(
                                  'Vanguard',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.dmSerifDisplay(
                                    color: Colors.white,
                                    fontSize: 54,
                                    height: 1,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Vanguard gives your delivery enhanced handling, priority support, trusted rider prioritisation, and stronger custody tracking for important items.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.78),
                                    fontSize: 17,
                                    height: 1.55,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Optional add-on at checkout — £1.99',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 42),
                          Text(
                            'Vanguard exists for deliveries where trust matters more than speed.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.dmSerifDisplay(
                              color: Colors.white,
                              fontSize: 32,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 24),
                          LayoutBuilder(builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 700;
                            return Flex(
                              direction:
                                  stacked ? Axis.vertical : Axis.horizontal,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: features.map((feature) {
                                final card = glass(Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(feature.$1, color: blue),
                                    const SizedBox(height: 14),
                                    Text(feature.$2,
                                        style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 8),
                                    Text(feature.$3,
                                        style: GoogleFonts.inter(
                                            color: Colors.white
                                                .withValues(alpha: 0.70),
                                            height: 1.45)),
                                  ],
                                ));
                                return stacked
                                    ? Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: card)
                                    : Expanded(
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(right: 12),
                                          child: card,
                                        ),
                                      );
                              }).toList(),
                            );
                          }),
                          const SizedBox(height: 24),
                          glass(Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _VanguardPageHeading('Custody preview'),
                              const SizedBox(height: 18),
                              for (var i = 0; i < timeline.length; i++)
                                _VanguardTimelineRow(
                                  label: timeline[i],
                                  last: i == timeline.length - 1,
                                ),
                            ],
                          )),
                          const SizedBox(height: 24),
                          LayoutBuilder(builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 700;
                            final when = glass(_VanguardListSection(
                                title: 'When to use it', items: useCases));
                            final adds = glass(_VanguardListSection(
                                title: 'What £1.99 adds', items: additions));
                            if (stacked) {
                              return Column(
                                children: [
                                  when,
                                  const SizedBox(height: 14),
                                  adds
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: when),
                                const SizedBox(width: 14),
                                Expanded(child: adds),
                              ],
                            );
                          }),
                          const SizedBox(height: 24),
                          glass(Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _VanguardPageHeading('Important'),
                              const SizedBox(height: 10),
                              Text(
                                'Vanguard is not insurance. It does not provide reimbursement, financial cover, or guarantees. Vanguard provides a higher standard of handling, visibility, verification, rider prioritisation, and support.',
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.76),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          )),
                          const SizedBox(height: 24),
                          glass(_VanguardListSection(
                            title: 'Included automatically',
                            items: included,
                            footer:
                                'These deliveries already include Vanguard-level handling at no extra cost.',
                          )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VanguardPageBackground extends StatelessWidget {
  final Widget child;

  const _VanguardPageBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xff07090f);
    const blue = Color(0xff3b82f6);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.15,
          colors: [blue.withValues(alpha: 0.10), navy],
        ),
      ),
      child: child,
    );
  }
}

class _VanguardPageHeading extends StatelessWidget {
  final String text;

  const _VanguardPageHeading(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.dmSerifDisplay(
          color: Colors.white,
          fontSize: 28,
        ),
      );
}

class _VanguardListSection extends StatelessWidget {
  final String title;
  final List<String> items;
  final String? footer;

  const _VanguardListSection({
    required this.title,
    required this.items,
    this.footer,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VanguardPageHeading(title),
          const SizedBox(height: 14),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: Color(0xff3b82f6), size: 18),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(item,
                        style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(footer!,
                style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.68), height: 1.45)),
          ],
        ],
      );
}

class _VanguardTimelineRow extends StatelessWidget {
  final String label;
  final bool last;

  const _VanguardTimelineRow({required this.label, required this.last});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xff3b82f6),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff3b82f6).withValues(alpha: 0.18),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Text(label,
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

class _LegalDocumentPage extends StatelessWidget {
  final _CircumColors colors;
  final String title;
  final String documentPath;
  final VoidCallback onBack;

  const _LegalDocumentPage({
    super.key,
    required this.colors,
    required this.title,
    required this.documentPath,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colors.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.35,
            colors: [
              colors.adminAccent.withValues(alpha: 0.20),
              colors.adminGlow.withValues(alpha: 0.10),
              colors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Back to Circum',
                            onPressed: onBack,
                            icon: const Icon(Icons.arrow_back),
                          ),
                          const SizedBox(width: 8),
                          Image.asset(
                            'assets/images/circum_wordmark.png',
                            width: 126,
                          ),
                        ],
                      ),
                      const SizedBox(height: 42),
                      _GlassPanel(
                        colors: colors,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 18,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.gavel_outlined,
                                size: 40,
                                color: colors.adminAccent,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                title,
                                style: TextStyle(
                                  color: colors.text,
                                  fontSize:
                                      MediaQuery.sizeOf(context).width < 600
                                          ? 34
                                          : 48,
                                  height: 1.05,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'The current Circum $title is available as a PDF document.',
                                style: TextStyle(
                                  color: colors.mutedText,
                                  fontSize: 17,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 26),
                              FilledButton.icon(
                                onPressed: () => launchUrl(
                                  Uri.base.resolve(documentPath),
                                  webOnlyWindowName: '_blank',
                                ),
                                icon: const Icon(Icons.open_in_new),
                                label: Text('Open $title'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      _GlobalLegalFooter(colors: colors, showWordmark: true),
                    ],
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

class _GiftsRequestPage extends StatefulWidget {
  final _CircumColors colors;
  final VoidCallback onBack;

  const _GiftsRequestPage({
    super.key,
    required this.colors,
    required this.onBack,
  });

  @override
  State<_GiftsRequestPage> createState() => _GiftsRequestPageState();
}

class _GiftsRequestPageState extends State<_GiftsRequestPage> {
  final _previewEmail = TextEditingController();
  final _previewPassword = TextEditingController();
  final _senderName = TextEditingController();
  final _senderEmail = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _recipientEmail = TextEditingController();
  final _deliveryAddress = TextEditingController();
  final _budget = TextEditingController();
  final _personalMessage = TextEditingController();
  final _notes = TextEditingController();
  final _clothingSize = TextEditingController();
  final _shoeSize = TextEditingController();
  final _ringSize = TextEditingController();
  final _height = TextEditingController();
  final _favouriteColours = TextEditingController();
  final _likedBrands = TextEditingController();
  final _dislikedBrands = TextEditingController();
  String _preferredFit = 'Regular';
  _ValidatedAddress? _validatedGiftAddress;
  String _relationship = 'Friend';
  String _occasion = 'Birthday';
  String _timeWindow = 'Afternoon';
  String _giftMode = 'gift_someone';
  String _anonymousGiftType = 'direct';
  String _senderRevealMode = 'anonymous_until_consent';
  String _selfGiftFrequency = 'one_off';
  final _customInterest = TextEditingController();
  final Set<String> _expandedInterestGroups = {'Style & beauty'};
  int _giftStep = 0;
  DateTime? _deliveryDate;
  final Set<String> _interests = {};
  XFile? _photo;
  bool _saving = false;
  bool _signingIn = false;
  String? _message;
  List<Map<String, dynamic>> _requests = const [];
  Map<String, dynamic>? _activeGiftStory;

  static const _relationships = [
    'Partner',
    'Husband',
    'Wife',
    'Boyfriend',
    'Girlfriend',
    'Fiancé',
    'Fiancée',
    'Crush',
    'Date',
    'Mother',
    'Father',
    'Parent',
    'Stepmother',
    'Stepfather',
    'Son',
    'Daughter',
    'Child',
    'Brother',
    'Sister',
    'Sibling',
    'Grandmother',
    'Grandfather',
    'Grandparent',
    'Grandson',
    'Granddaughter',
    'Grandchild',
    'Aunt',
    'Uncle',
    'Niece',
    'Nephew',
    'Cousin',
    'Godmother',
    'Godfather',
    'Godchild',
    'In-law',
    'Friend',
    'Best Friend',
    'Close Friend',
    'Childhood Friend',
    'Family Friend',
    'Housemate',
    'Neighbour',
    'Colleague',
    'Manager',
    'Boss',
    'Employee',
    'Mentor',
    'Mentee',
    'Client',
    'Customer',
    'Business Partner',
    'Teacher',
    'Tutor',
    'Student',
    'Coach',
    'Team Member',
    'Church Member',
    'Pastor',
    'Community Member',
    'Volunteer',
    'Carer',
    'Support Worker',
    'Local Hero',
    'Myself',
    'Anonymous Recipient',
    'Secret Recipient',
    'Someone Special',
    'Other'
  ];
  static const _occasions = [
    'Birthday',
    'Anniversary',
    'Wedding',
    'Engagement',
    'Proposal',
    'Graduation',
    'Promotion',
    'Retirement',
    'New Job',
    'New Business',
    'Business Milestone',
    'Work Anniversary',
    'Passing Exams',
    'Academic Achievement',
    'New Baby',
    'Baby Shower',
    'Gender Reveal',
    'Adoption',
    'Housewarming',
    'First Home',
    'Moving Home',
    'Family Reunion',
    'Thank You',
    'Appreciation',
    'Recognition',
    'Well Done',
    'Congratulations',
    'Good Luck',
    'Welcome',
    'Welcome Back',
    'Get Well Soon',
    'Recovery',
    'Hospital Discharge',
    'Encouragement',
    'Thinking Of You',
    'Difficult Time',
    'Bereavement',
    'Sympathy',
    'Care Package',
    'Date Night',
    'Romantic Surprise',
    "Valentine's Day",
    'First Anniversary',
    'Reconciliation',
    'Just Because I Love You',
    'Christmas',
    'New Year',
    'Easter',
    "Mother's Day",
    "Father's Day",
    'Eid al-Fitr',
    'Eid al-Adha',
    'Diwali',
    'Hanukkah',
    'Lunar New Year',
    'Thanksgiving',
    'Halloween',
    'Baptism',
    'Christening',
    'Confirmation',
    'First Communion',
    'Bar Mitzvah',
    'Bat Mitzvah',
    'Religious Celebration',
    'First Day of School',
    'School Graduation',
    'Passing Driving Test',
    'University Acceptance',
    'Sports Achievement',
    'Anonymous Kindness',
    'Community Campaign',
    'Bringing London Together',
    'Local Hero',
    'Volunteer Recognition',
    'Just Because',
    'Random Act of Kindness',
    'Surprise Gift',
    'Missing You',
    'Friendship Celebration',
    'Apology',
    'Bank Holiday Surprise',
    'Leaving Gift',
    'Achievement Reward',
    'Other'
  ];
  static const _interestOptions = [
    'Fashion',
    'Beauty',
    'Makeup',
    'Skincare',
    'Tech',
    'Gaming',
    'Gym',
    'Travel',
    'Books',
    'Food',
    'Cooking',
    'Coffee',
    'Tea',
    'Christian',
    'Muslim',
    'Jewish',
    'Spiritual',
    'Charity',
    'Aviation',
    'Music',
    'Luxury',
    'Minimalist',
    'Home Decor',
    'Fragrance',
    'Art',
    'Design',
    'Architecture',
    'Gardening',
    'Film',
    'Theatre',
    'Sports',
    'Football',
    'Running',
    'Cycling',
    'Swimming',
    'Photography',
    'Cars',
    'Motorcycles',
    'Jewellery',
    'Watches',
    'Writing',
    'Animals',
    'Nature',
    'Sustainability',
    'Collectibles',
    'Restaurants',
    'Fine Dining',
    'Michelin Dining',
    'Street Food',
    'Brunch',
    'Afternoon Tea',
    'Luxury Travel',
    'City Breaks',
    'Adventure Travel',
    'Cruises',
    'Hotels',
    'Spa Experiences',
    'Wellness Retreats',
    'Luxury Fashion',
    'Streetwear',
    'Handbags',
    'Sneakers',
    'Interior Design',
    'Home Fragrance',
    'Musicals',
    'Opera',
    'Live Music',
    'Festivals',
    'Cinema',
    'TV & Streaming',
    'Business',
    'Entrepreneurship',
    'Investing',
    'Startups',
    'Personal Development',
    'Leadership',
    'Wine Appreciation',
    'Whisky Appreciation',
    'Craft Beverages',
  ];
  static const _relationshipMoments = {
    'Someone Else': 'gift_someone',
    'Anonymous Gift': 'anonymous_gift',
    'Myself': 'gift_myself',
  };
  static const _interestGroups = {
    'Style & beauty': [
      'Fashion',
      'Luxury Fashion',
      'Streetwear',
      'Beauty',
      'Makeup',
      'Skincare',
      'Fragrance',
      'Home Fragrance',
      'Jewellery',
      'Watches',
      'Handbags',
      'Sneakers',
    ],
    'Food, drink & dining': [
      'Food',
      'Cooking',
      'Coffee',
      'Tea',
      'Restaurants',
      'Fine Dining',
      'Michelin Dining',
      'Street Food',
      'Brunch',
      'Afternoon Tea',
      'Wine Appreciation',
      'Whisky Appreciation',
      'Craft Beverages',
    ],
    'Travel & experiences': [
      'Travel',
      'Luxury Travel',
      'City Breaks',
      'Adventure Travel',
      'Cruises',
      'Hotels',
      'Spa Experiences',
      'Wellness Retreats',
      'Aviation',
      'Festivals',
    ],
    'Culture & creativity': [
      'Books',
      'Writing',
      'Art',
      'Design',
      'Architecture',
      'Interior Design',
      'Music',
      'Live Music',
      'Film',
      'Cinema',
      'TV & Streaming',
      'Theatre',
      'Musicals',
      'Opera',
      'Photography',
    ],
    'Lifestyle & passions': [
      'Tech',
      'Gaming',
      'Gym',
      'Sports',
      'Football',
      'Running',
      'Cycling',
      'Swimming',
      'Cars',
      'Motorcycles',
      'Gardening',
      'Animals',
      'Nature',
      'Collectibles',
    ],
    'Values & growth': [
      'Christian',
      'Muslim',
      'Jewish',
      'Spiritual',
      'Charity',
      'Sustainability',
      'Minimalist',
      'Home Decor',
      'Luxury',
      'Business',
      'Entrepreneurship',
      'Investing',
      'Startups',
      'Personal Development',
      'Leadership',
    ],
  };

  @override
  void initState() {
    super.initState();
    _loadAccountAndRequests();
  }

  @override
  void dispose() {
    for (final controller in [
      _senderName,
      _senderEmail,
      _recipientName,
      _recipientPhone,
      _recipientEmail,
      _deliveryAddress,
      _budget,
      _personalMessage,
      _notes,
      _clothingSize,
      _shoeSize,
      _ringSize,
      _height,
      _favouriteColours,
      _likedBrands,
      _dislikedBrands,
      _customInterest,
      _previewEmail,
      _previewPassword
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAccountAndRequests() async {
    await _ensureCircumFirebaseReady();
    final storyToken = Uri.base.queryParameters['giftStoryToken'];
    if (storyToken != null && storyToken.trim().isNotEmpty) {
      try {
        final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('resolveGiftStoryAccess');
        final result = await callable.call({'token': storyToken.trim()});
        final payload = Map<String, dynamic>.from(result.data as Map);
        final story = Map<String, dynamic>.from(payload['story'] as Map);
        if (mounted && _giftStoryCanOpen(story)) {
          setState(() => _activeGiftStory = story);
        }
      } catch (error) {
        debugPrint('Gift Story secure link error: $error');
        if (mounted) {
          setState(() => _message =
              'This Gift Story link is invalid, expired, or not available yet.');
        }
      }
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _senderEmail.text = user.email ?? '';
    _senderName.text = user.displayName ?? '';
    try {
      final senderSnapshot = await FirebaseFirestore.instance
          .collection('giftRequests')
          .where('senderId', isEqualTo: user.uid)
          .limit(20)
          .get();
      final recipientSnapshot = await FirebaseFirestore.instance
          .collection('giftRequests')
          .where('recipientEmail', isEqualTo: (user.email ?? '').toLowerCase())
          .limit(20)
          .get();
      final byId = <String, Map<String, dynamic>>{};
      for (final doc in [...senderSnapshot.docs, ...recipientSnapshot.docs]) {
        byId[doc.id] = <String, dynamic>{'id': doc.id, ...doc.data()};
      }
      if (!mounted) return;
      setState(() => _requests = byId.values.toList());
      await _handleGiftPaymentReturn();
      final storyId = Uri.base.queryParameters['giftStory'];
      if (storyId != null && mounted) {
        Map<String, dynamic>? story;
        for (final request in _requests) {
          if ('${request['id']}' == storyId) {
            story = request;
            break;
          }
        }
        if (_giftStoryCanOpen(story)) {
          setState(() => _activeGiftStory = story);
        }
      }
    } catch (error) {
      debugPrint('Gift request history error: $error');
    }
  }

  Future<void> _signInToPreview() async {
    if (_signingIn) return;
    final email = _previewEmail.text.trim().toLowerCase();
    setState(() {
      _signingIn = true;
      _message = null;
    });
    try {
      await _ensureCircumFirebaseReady();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _previewPassword.text,
      );
      await _loadAccountAndRequests();
      if (mounted) setState(() => _message = 'Signed in.');
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() => _message = switch (error.code) {
              'invalid-credential' ||
              'wrong-password' =>
                'The email or password is incorrect.',
              'invalid-email' => 'Enter a valid email address.',
              _ => 'We could not sign you in. Please try again.',
            });
      }
    } catch (error) {
      debugPrint('Gifts sign-in error: $error');
      if (mounted)
        setState(
            () => _message = 'We could not sign you in. Please try again.');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _handleGiftPaymentReturn() async {
    final result = Uri.base.queryParameters['gift_payment'];
    if (result == 'cancelled') {
      if (mounted)
        setState(() => _message =
            'Payment was cancelled. Your gift has not been submitted.');
      return;
    }
    if (result != 'success') return;
    final giftDraftId = Uri.base.queryParameters['giftDraftId'];
    final sessionId = Uri.base.queryParameters['session_id'];
    if (giftDraftId == null || sessionId == null) return;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('finalizeGiftPayment')
          .call({
        'giftDraftId': giftDraftId,
        'sessionId': sessionId,
      });
      if (mounted)
        setState(() => _message =
            'Payment received. Your gift experience is now submitted for review.');
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
          'Gift payment finalization error: ${error.code} ${error.message}');
      if (mounted)
        setState(() => _message = error.message ??
            'We could not confirm payment yet. Please refresh shortly.');
    }
  }

  Future<void> _pickPhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _message = 'Sign in to create a gift experience.');
      return;
    }
    final grossBudget = double.tryParse(_budget.text.trim());
    final validation = GiftRequestPolicy.validate(
      senderEmail: _senderEmail.text,
      recipientName: _recipientName.text,
      recipientPhone: _recipientPhone.text,
      recipientEmail: _recipientEmail.text,
      relationship: _relationship,
      occasion: _occasion,
      deliveryAddress: _deliveryAddress.text,
      deliveryDate: _deliveryDate,
      grossBudget: grossBudget,
    );
    if (validation != null) {
      setState(() => _message = validation);
      return;
    }
    if (_validatedGiftAddress == null) {
      setState(() => _message =
          'Please select a verified address from the suggestions, or confirm the manual address.');
      return;
    }
    final rothBalance = await _fetchRothBalanceForUser(user);
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review your gift experience'),
        content: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Occasion: $_occasion'),
            Text('Recipient: ${_recipientName.text.trim()}'),
            Text(
                'Contact: ${_recipientPhone.text.trim()} · ${_recipientEmail.text.trim()}'),
            Text('Delivery: ${_deliveryAddress.text.trim()}'),
            Text('Date: ${_adminDateText(_deliveryDate)} · $_timeWindow'),
            _CircumPaymentSummary(
              colors: widget.colors,
              serviceName: 'Gifts by Circum Experience',
              totalLabel: 'Total Experience Budget',
              total: grossBudget!,
              rothAvailable: rothBalance,
              ctaLabel: 'Gift This Experience',
            ),
            if (_personalMessage.text.trim().isNotEmpty)
              Text('Message: ${_personalMessage.text.trim()}'),
            const SizedBox(height: 12),
            const Text(
                'Gift contents remain confidential before delivery. No products, brands, retailers or basket details are shown.'),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Proceed to Payment')),
        ],
      ),
    );
    if (proceed != true) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final doc =
          FirebaseFirestore.instance.collection('giftPaymentDrafts').doc();
      final photoUrls = <String>[];
      if (_photo != null) {
        final bytes = await _photo!.readAsBytes();
        if (bytes.length > 8 * 1024 * 1024) {
          throw StateError('Photo must be smaller than 8 MB.');
        }
        final ref = FirebaseStorage.instance
            .ref('gift_requests/${user.uid}/${doc.id}.jpg');
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        photoUrls.add(await ref.getDownloadURL());
      }
      await doc.set({
        'senderId': user.uid,
        'senderName': _senderName.text.trim(),
        'senderEmail': _senderEmail.text.trim().toLowerCase(),
        'recipientName': _recipientName.text.trim(),
        'recipientPhone': _recipientPhone.text.trim(),
        'recipientEmail': _recipientEmail.text.trim().toLowerCase(),
        'recipientContact':
            '${_recipientPhone.text.trim()} · ${_recipientEmail.text.trim().toLowerCase()}',
        'relationship': _relationship,
        'occasion': _occasion,
        'giftMode': _giftMode,
        'anonymousGiftType':
            _giftMode == 'anonymous_gift' ? _anonymousGiftType : null,
        'senderRevealMode': _giftMode == 'anonymous_gift'
            ? _senderRevealMode
            : 'reveal_immediately',
        'senderRevealConsent':
            _giftMode == 'anonymous_gift' ? 'not_requested' : 'granted',
        'recipientRevealRequestStatus': 'none',
        'selfGiftFrequency':
            _giftMode == 'gift_myself' ? _selfGiftFrequency : null,
        'deliveryAddress': _deliveryAddress.text.trim(),
        'deliveryAddressData': _validatedGiftAddress!.toJson(),
        'deliveryPostcode': _validatedGiftAddress!.postcode,
        'deliveryCity': _validatedGiftAddress!.city,
        'deliveryCountry': _validatedGiftAddress!.country,
        'deliveryDate': Timestamp.fromDate(_deliveryDate!),
        'deliveryTimeWindow': _timeWindow,
        'budget': grossBudget,
        'grossBudget': grossBudget,
        'grossGiftBudget': grossBudget,
        'estimatedStripeFee':
            GiftRequestPolicy.estimatedStripeFee(grossBudget!),
        'netGiftBudgetAfterFees':
            GiftRequestPolicy.estimatedNetGiftBudget(grossBudget),
        'estimatedNetGiftBudget':
            GiftRequestPolicy.estimatedNetGiftBudget(grossBudget!),
        'budgetStatus': 'pending_allocation',
        'personalMessage': _personalMessage.text.trim(),
        'interests': _interests.toList(),
        'photoUrls': photoUrls,
        'notes': _notes.text.trim(),
        'sizesAndPreferences': {
          'clothingSize': _clothingSize.text.trim(),
          'shoeSize': _shoeSize.text.trim(),
          'ringSize': _ringSize.text.trim(),
          'preferredFit': _preferredFit,
          'height': _height.text.trim(),
          'favouriteColours': _favouriteColours.text.trim(),
          'brandsLiked': _likedBrands.text.trim(),
          'brandsDisliked': _dislikedBrands.text.trim(),
        },
        'giftType':
            _giftMode == 'anonymous_gift' && _anonymousGiftType == 'campaign'
                ? 'campaign'
                : 'standard',
        'paymentStatus': 'payment_pending',
        'giftStatus': 'draft',
        'status': 'draft',
        'giftStoryEnabled': true,
        'giftStoryApproved': true,
        'giftStoryShareEnabled': true,
        'giftStorySharePrivacy': 'private',
        'giftStoryMusicEnabled': false,
        'giftStoryCustomAudioUrl': null,
        'giftStoryRevealViewedAt': null,
        'senderMessageText': _personalMessage.text.trim(),
        'senderMessageVideoUrl': '',
        'interestTags': _interests.toList(),
        'storyTheme': 'iridescent',
        'assignedAdminId': null,
        'irisSuggestion': 'Pending IRIS gift recommendation',
        'adminDecision': '',
        'internalNotes': '',
        'recipientContentConsent': 'pending',
        'senderContentConsent': 'pending',
        'consentCapturedAt': null,
        'consentVersion': 'gifts-social-v1',
        'consentNotes': '',
        'allowCircumSocialUse': false,
        'allowBrandTagging': false,
        'allowReactionRecording': false,
        'allowPublicPosting': false,
        'allowAnonymousPosting': false,
        'contentUsageScope': 'private',
        'contentConsentWithdrawnAt': null,
        'contentStatus': 'not_started',
        'campaignId':
            _anonymousGiftType == 'campaign' ? 'bringing-london-closer' : null,
        'campaignName':
            _anonymousGiftType == 'campaign' ? 'Bringing London Closer' : null,
        'campaignTagline': _anonymousGiftType == 'campaign'
            ? '100 Londoners. 100 gifts. 100 stories.'
            : null,
        'campaignType':
            _anonymousGiftType == 'campaign' ? 'anonymous_gifting' : null,
        'participantConsentRequired': _anonymousGiftType == 'campaign',
        'recordingConsentRequired': _anonymousGiftType == 'campaign',
        'mutualRevealAllowed': _anonymousGiftType == 'campaign',
        'anonymousByDefault': _giftMode == 'anonymous_gift',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final payment = await FirebaseFunctions.instance
          .httpsCallable('createGiftPayment')
          .call({'giftDraftId': doc.id});
      final paymentData = Map<String, dynamic>.from(payment.data as Map);
      if (paymentData['walletPaidInFull'] == true) {
        await _loadAccountAndRequests();
        if (!mounted) return;
        setState(() => _message =
            'Your gift request has been submitted and paid with Roth.');
        return;
      }
      final checkoutUrl = Uri.tryParse('${paymentData['url'] ?? ''}');
      if (checkoutUrl == null || checkoutUrl.host.isEmpty) {
        throw StateError(
            'Stripe Checkout could not be opened. Please try again.');
      }
      final total = (paymentData['orderTotalGbp'] as num?)?.toDouble() ??
          grossBudget ??
          0;
      final rothApplied =
          (paymentData['walletContributionGbp'] as num?)?.toDouble() ?? 0;
      final cardRemaining =
          (paymentData['remainingStripeAmountGbp'] as num?)?.toDouble() ??
              math.max(0, total - rothApplied);
      setState(() => _message =
          'Complete payment to submit your gift request. Total Experience Budget: £${total.toStringAsFixed(2)} · Roth Applied: £${rothApplied.toStringAsFixed(2)} · Card Payment: £${cardRemaining.toStringAsFixed(2)}');
      final opened = await launchUrl(checkoutUrl, webOnlyWindowName: '_self');
      if (!opened)
        throw StateError(
            'Stripe Checkout could not be opened. Please try again.');
    } catch (error) {
      debugPrint('Gift request submit error: $error');
      if (mounted)
        setState(() => _message = error is StateError
            ? error.message
            : error is FirebaseFunctionsException
                ? (error.message ??
                    'Could not start Stripe Checkout. Please try again.')
                : 'Could not start Stripe Checkout. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final signedIn = FirebaseAuth.instance.currentUser != null;
    final activeStory = _activeGiftStory;
    if (activeStory != null) {
      return _GiftStoryViewer(
        colors: colors,
        gift: activeStory,
        onClose: () => setState(() => _activeGiftStory = null),
      );
    }
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: ListView(
          padding:
              EdgeInsets.fromLTRB(narrow ? 16 : 28, 16, narrow ? 16 : 28, 48),
          children: [
            Row(children: [
              IconButton(
                  onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
              Image.asset('assets/images/circum_wordmark.png', width: 126),
            ]),
            const SizedBox(height: 22),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                          child: Image.asset(
                              'assets/images/gifts_by_circum_logo.jpg',
                              width: narrow ? 280 : 390,
                              semanticLabel: 'Gifts by Circum logo')),
                      const SizedBox(height: 12),
                      Text('Thoughtful gifting, delivered by Circum',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: colors.mutedText,
                              fontSize: 18,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 28),
                      Text(
                          'Tell us the occasion, the person, and your budget. Circum creates and delivers a thoughtful gift experience.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: colors.text,
                              fontSize: narrow ? 25 : 34,
                              height: 1.2,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 24),
                      Center(
                        child: Chip(
                          avatar: const Icon(Icons.lock_clock, size: 18),
                          label: const Text('Early Access Beta'),
                          backgroundColor:
                              colors.adminAccent.withValues(alpha: 0.16),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!signedIn)
                        _GlassPanel(
                          colors: colors,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Sign in to Gifts',
                                style: TextStyle(
                                  color: colors.text,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Sign in to create and pay for a curated gift experience.',
                                style: TextStyle(
                                  color: colors.mutedText,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _giftField(
                                _previewEmail,
                                'Email address',
                                Icons.email_outlined,
                                type: TextInputType.emailAddress,
                              ),
                              _giftField(
                                _previewPassword,
                                'Password',
                                Icons.lock_outline,
                                obscure: true,
                              ),
                              if (_message != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _message!,
                                  style: TextStyle(
                                    color: colors.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _signingIn ? null : _signInToPreview,
                                icon: _signingIn
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.lock_open),
                                label: Text(_signingIn
                                    ? 'Signing in...'
                                    : 'Sign in and continue'),
                              ),
                            ],
                          ),
                        ),
                      if (signedIn) ...[
                        _GlassPanel(
                          colors: colors,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('How Gifts Works',
                                    style: TextStyle(
                                        color: colors.text,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900)),
                                const SizedBox(height: 10),
                                ...const [
                                  '1. Tell us about the recipient.',
                                  '2. Set your budget.',
                                  '3. IRIS creates private recommendations.',
                                  '4. The Gifts Team reviews and approves the experience.',
                                  '5. We source, prepare and deliver.',
                                  '6. The recipient discovers the surprise.',
                                ].map((step) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(step))),
                                const SizedBox(height: 8),
                                const Text(
                                    'Gift contents are intentionally kept confidential before delivery. Gifts by Circum is a curated gifting experience, not a traditional online shop.'),
                              ]),
                        ),
                        const SizedBox(height: 14),
                        _giftConciergeFlow(colors, narrow),
                        if (false)
                          _GlassPanel(
                              colors: colors,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text('Create the experience',
                                        style: TextStyle(
                                            color: colors.text,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 16),
                                    DropdownButtonFormField<String>(
                                      initialValue: _giftMode,
                                      decoration: const InputDecoration(
                                          labelText: 'Gift mode'),
                                      items: const {
                                        'gift_someone': 'Gift someone',
                                        'gift_myself': 'Gift myself',
                                        'anonymous_gift': 'Anonymous gift',
                                      }
                                          .entries
                                          .map((entry) => DropdownMenuItem(
                                              value: entry.key,
                                              child: Text(entry.value)))
                                          .toList(),
                                      onChanged: (value) => setState(
                                          () => _giftMode = value ?? _giftMode),
                                    ),
                                    if (_giftMode == 'anonymous_gift') ...[
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String>(
                                        initialValue: _anonymousGiftType,
                                        decoration: const InputDecoration(
                                            labelText: 'Anonymous gift type'),
                                        items: const {
                                          'direct': 'Direct anonymous gift',
                                          'campaign':
                                              'Campaign · Bringing London Closer',
                                        }
                                            .entries
                                            .map((entry) => DropdownMenuItem(
                                                value: entry.key,
                                                child: Text(entry.value)))
                                            .toList(),
                                        onChanged: (value) => setState(() =>
                                            _anonymousGiftType =
                                                value ?? _anonymousGiftType),
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String>(
                                        initialValue: _senderRevealMode,
                                        decoration: const InputDecoration(
                                            labelText: 'Identity reveal'),
                                        items: const {
                                          'anonymous_forever':
                                              'Anonymous forever',
                                          'reveal_after_delivery':
                                              'Reveal after delivery',
                                          'anonymous_until_consent':
                                              'Reveal only with later consent',
                                          'reveal_immediately':
                                              'Reveal immediately',
                                        }
                                            .entries
                                            .map((entry) => DropdownMenuItem(
                                                value: entry.key,
                                                child: Text(entry.value)))
                                            .toList(),
                                        onChanged: (value) => setState(() =>
                                            _senderRevealMode =
                                                value ?? _senderRevealMode),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Circum knows who arranged the gift for safety and fraud prevention. The recipient only sees the sender identity when consent permits or disclosure is legally required.',
                                        style: TextStyle(
                                            color: colors.mutedText,
                                            fontSize: 12),
                                      ),
                                    ],
                                    if (_giftMode == 'gift_myself') ...[
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String>(
                                        initialValue: _selfGiftFrequency,
                                        decoration: const InputDecoration(
                                            labelText: 'Self-gift frequency'),
                                        items: const {
                                          'one_off': 'One-off',
                                          'monthly': 'Monthly',
                                          'quarterly': 'Quarterly',
                                          'custom': 'Custom',
                                        }
                                            .entries
                                            .map((entry) => DropdownMenuItem(
                                                value: entry.key,
                                                child: Text(entry.value)))
                                            .toList(),
                                        onChanged: (value) => setState(() =>
                                            _selfGiftFrequency =
                                                value ?? _selfGiftFrequency),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    Text('Who is receiving?',
                                        style: TextStyle(
                                            color: colors.text,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 10),
                                    _giftField(_senderName, 'Sender name',
                                        Icons.person_outline),
                                    _giftField(_senderEmail, 'Sender email',
                                        Icons.email_outlined,
                                        type: TextInputType.emailAddress),
                                    _giftField(_recipientName, 'Recipient name',
                                        Icons.redeem_outlined),
                                    _giftField(
                                        _recipientPhone,
                                        'Recipient phone',
                                        Icons.contact_phone_outlined),
                                    _giftField(_recipientEmail,
                                        'Recipient email', Icons.email_outlined,
                                        type: TextInputType.emailAddress),
                                    Text(
                                        _giftMode == 'gift_myself'
                                            ? 'Tell us about yourself'
                                            : 'Tell us about them',
                                        style: TextStyle(
                                            color: colors.text,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 10),
                                    Row(children: [
                                      Expanded(
                                          child: DropdownButtonFormField<
                                                  String>(
                                              initialValue: _relationship,
                                              decoration: const InputDecoration(
                                                  labelText: 'Relationship'),
                                              items: _relationships
                                                  .map((v) => DropdownMenuItem(
                                                      value: v, child: Text(v)))
                                                  .toList(),
                                              onChanged: (v) => setState(() =>
                                                  _relationship =
                                                      v ?? _relationship))),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: DropdownButtonFormField<
                                                  String>(
                                              initialValue: _occasion,
                                              decoration: const InputDecoration(
                                                  labelText: 'Occasion'),
                                              items: _occasions
                                                  .map((v) => DropdownMenuItem(
                                                      value: v, child: Text(v)))
                                                  .toList(),
                                              onChanged: (v) => setState(() =>
                                                  _occasion = v ?? _occasion))),
                                    ]),
                                    const SizedBox(height: 12),
                                    Text('Sizes and preferences',
                                        style: TextStyle(
                                            color: colors.text,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 10),
                                    Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          SizedBox(
                                              width: 180,
                                              child: _giftField(
                                                  _clothingSize,
                                                  'Clothing size',
                                                  Icons.checkroom)),
                                          SizedBox(
                                              width: 180,
                                              child: _giftField(_shoeSize,
                                                  'Shoe size', Icons.hiking)),
                                          SizedBox(
                                              width: 180,
                                              child: _giftField(
                                                  _ringSize,
                                                  'Ring size',
                                                  Icons.circle_outlined)),
                                          SizedBox(
                                              width: 180,
                                              child: _giftField(_height,
                                                  'Height', Icons.height)),
                                        ]),
                                    DropdownButtonFormField<String>(
                                        initialValue: _preferredFit,
                                        decoration: const InputDecoration(
                                            labelText: 'Preferred fit'),
                                        items: const [
                                          'Slim',
                                          'Regular',
                                          'Relaxed',
                                          'Oversized'
                                        ]
                                            .map((v) => DropdownMenuItem(
                                                value: v, child: Text(v)))
                                            .toList(),
                                        onChanged: (v) => setState(() =>
                                            _preferredFit =
                                                v ?? _preferredFit)),
                                    _giftField(
                                        _favouriteColours,
                                        'Favourite colours',
                                        Icons.palette_outlined),
                                    _giftField(_likedBrands, 'Brands they like',
                                        Icons.favorite_border),
                                    _giftField(_dislikedBrands,
                                        'Brands they dislike', Icons.block),
                                    Text('Delivery details',
                                        style: TextStyle(
                                            color: colors.text,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 10),
                                    _AddressField(
                                        colors: colors,
                                        icon: Icons.location_on_outlined,
                                        label: 'Delivery address',
                                        controller: _deliveryAddress,
                                        verified:
                                            _validatedGiftAddress?.isVerified ==
                                                true,
                                        onSelected: (address) => setState(() =>
                                            _validatedGiftAddress = address),
                                        onEdited: (_) => setState(
                                            () => _validatedGiftAddress = null),
                                        enableFreeLookup: true,
                                        verifiedMessage:
                                            'Verified delivery address selected'),
                                    Row(children: [
                                      Expanded(
                                          child: OutlinedButton.icon(
                                              onPressed: () async {
                                                final date = await showDatePicker(
                                                    context: context,
                                                    firstDate: DateTime.now(),
                                                    lastDate: DateTime.now()
                                                        .add(const Duration(
                                                            days: 365)),
                                                    initialDate:
                                                        _deliveryDate ??
                                                            DateTime.now().add(
                                                                const Duration(
                                                                    days: 2)));
                                                if (date != null)
                                                  setState(() =>
                                                      _deliveryDate = date);
                                              },
                                              icon: const Icon(
                                                  Icons.calendar_month),
                                              label: Text(_deliveryDate == null
                                                  ? 'Preferred delivery date'
                                                  : _adminDateText(
                                                      _deliveryDate)))),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: DropdownButtonFormField<
                                                  String>(
                                              initialValue: _timeWindow,
                                              decoration: const InputDecoration(
                                                  labelText: 'Time window'),
                                              items: const [
                                                'Morning',
                                                'Afternoon',
                                                'Evening'
                                              ]
                                                  .map((v) => DropdownMenuItem(
                                                      value: v, child: Text(v)))
                                                  .toList(),
                                              onChanged: (v) => setState(() =>
                                                  _timeWindow =
                                                      v ?? _timeWindow))),
                                    ]),
                                    const SizedBox(height: 12),
                                    Text('Gift budget',
                                        style: TextStyle(
                                            color: colors.text,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 8),
                                    Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          50,
                                          100,
                                          250,
                                          500,
                                          1000,
                                          1500
                                        ]
                                            .map((value) => ChoiceChip(
                                                label: Text('£$value'),
                                                selected:
                                                    _budget.text == '$value',
                                                onSelected: (_) => setState(
                                                    () => _budget.text =
                                                        '$value')))
                                            .toList()),
                                    const SizedBox(height: 8),
                                    _giftField(
                                        _budget,
                                        'Gift budget (minimum £50)',
                                        Icons.payments_outlined,
                                        type: const TextInputType
                                            .numberWithOptions(decimal: true)),
                                    Text('Interests',
                                        style: TextStyle(
                                            color: colors.text,
                                            fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 8),
                                    Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: _interestOptions
                                            .map((interest) => FilterChip(
                                                label: Text(interest),
                                                selected: _interests
                                                    .contains(interest),
                                                onSelected: (selected) =>
                                                    setState(() => selected
                                                        ? _interests
                                                            .add(interest)
                                                        : _interests
                                                            .remove(interest))))
                                            .toList()),
                                    const SizedBox(height: 12),
                                    Text('Additional information',
                                        style: TextStyle(
                                            color: colors.text,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 8),
                                    _giftField(
                                        _personalMessage,
                                        'Personal message',
                                        Icons.chat_bubble_outline,
                                        lines: 3),
                                    _giftField(_notes, 'Additional Information',
                                        Icons.notes,
                                        lines: 3),
                                    Text(
                                        'Record allergies, medical conditions, dietary requirements, religious considerations, sensitivities, accessibility requirements, favourite colours, favourite brands, dislikes, or any special requests.',
                                        style: TextStyle(
                                            color: colors.mutedText,
                                            fontSize: 12)),
                                    OutlinedButton.icon(
                                        onPressed: _pickPhoto,
                                        icon: const Icon(
                                            Icons.add_a_photo_outlined),
                                        label: Text(_photo == null
                                            ? 'Add optional recipient photo'
                                            : 'Photo selected · Replace')),
                                    if (_photo != null)
                                      Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                              onPressed: () =>
                                                  setState(() => _photo = null),
                                              icon: const Icon(Icons.close),
                                              label:
                                                  const Text('Remove photo'))),
                                    if (_message != null)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 12),
                                          child: Text(_message!,
                                              style: TextStyle(
                                                  color: colors.text,
                                                  fontWeight:
                                                      FontWeight.w700))),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                        onPressed: _saving ? null : _submit,
                                        icon: _saving
                                            ? const SizedBox.square(
                                                dimension: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : const Icon(Icons.card_giftcard),
                                        label: Text(_saving
                                            ? 'Preparing payment...'
                                            : 'Create Gift Experience'),
                                        style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 17))),
                                    const SizedBox(height: 8),
                                    Text(
                                        'The exact gift contents, supplier costs, and internal fulfilment plan remain private until delivery.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: colors.mutedText,
                                            fontSize: 12)),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Circum may ask to record or share a gift reaction. This is optional, and the gift can still be received if filming or public posting is declined.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: colors.mutedText,
                                          fontSize: 12),
                                    ),
                                  ])),
                      ],
                      const SizedBox(height: 22),
                      _giftMemoryVault(colors),
                      if (_requests.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Text('Your gift requests',
                            style: TextStyle(
                                color: colors.text,
                                fontSize: 22,
                                fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        ..._requests.map(
                          (request) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: colors.field,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.border),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.card_giftcard),
                              title: Text(
                                '${request['occasion']} for ${request['recipientName']}',
                              ),
                              subtitle: Text(
                                GiftRequestPolicy.senderStatus(
                                  '${request['status']}',
                                ),
                              ),
                              trailing: Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '£${((request['grossBudget'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                                  ),
                                  if (_giftStoryCanOpen(request))
                                    TextButton(
                                      onPressed: () => setState(
                                          () => _activeGiftStory = request),
                                      child: const Text('View Gift Story'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      _GlobalLegalFooter(colors: colors),
                    ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _giftStoryCanOpen(Map<String, dynamic>? request) {
    if (request == null) return false;
    final status =
        '${request['giftStatus'] ?? request['status']}'.toLowerCase();
    final delivered = status == 'delivered' || status == 'completed';
    return delivered &&
        request['giftStoryEnabled'] != false &&
        request['giftStoryApproved'] != false;
  }

  Widget _giftMemoryVault(_CircumColors colors) {
    final deliveredGifts = _requests.where((request) {
      final status =
          '${request['giftStatus'] ?? request['status']}'.toLowerCase();
      return status == 'delivered' || status == 'completed';
    }).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(colors: [
          colors.adminAccent.withValues(alpha: 0.18),
          colors.adminGlow.withValues(alpha: 0.10),
          colors.field.withValues(alpha: 0.62),
        ]),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_stories_outlined, color: colors.adminAccent),
            const SizedBox(width: 10),
            Text('Gift Memories',
                style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 8),
          Text(
            deliveredGifts.isEmpty
                ? 'Your delivered gift experiences will become lasting stories here.'
                : 'Revisit completed Gifts by Circum experiences and their stories.',
            style: TextStyle(color: colors.mutedText, height: 1.35),
          ),
          if (deliveredGifts.isEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Column(
                children: [
                  Icon(Icons.auto_stories_outlined,
                      color: colors.adminAccent, size: 34),
                  const SizedBox(height: 10),
                  Text('No Gift Memories yet',
                      style: TextStyle(
                          color: colors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  Text(
                    'After a gift is delivered, its approved Gift Story will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.mutedText),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            ...deliveredGifts.map((story) {
              final draft = _giftStoryOutputFromRequest(story);
              final storyReady = _giftStoryCanOpen(story);
              final videoReady = (draft.renderedVideoUrl ?? '').isNotEmpty;
              final recipientFirstName = draft.recipientName.trim().isEmpty
                  ? 'Recipient'
                  : draft.recipientName.trim().split(RegExp(r'\s+')).first;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(colors: [
                    colors.adminAccent.withValues(alpha: 0.12),
                    colors.field.withValues(alpha: 0.72),
                  ]),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.card_giftcard, color: colors.adminAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${draft.occasion} for $recipientFirstName',
                          style: TextStyle(
                              color: colors.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                      _HealthChip(label: 'Delivered'),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      'Created ${_adminDateText(story['createdAt'] ?? story['deliveryDate'])}',
                      style: TextStyle(color: colors.mutedText),
                    ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (storyReady)
                        FilledButton.icon(
                          onPressed: () =>
                              setState(() => _activeGiftStory = story),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('View Story'),
                        )
                      else
                        Chip(
                          avatar: const Icon(Icons.hourglass_top, size: 17),
                          label: const Text('Story preparing'),
                          backgroundColor: colors.field,
                        ),
                      if (videoReady)
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(
                            Uri.parse(draft.renderedVideoUrl!),
                            webOnlyWindowName: '_blank',
                          ),
                          icon: const Icon(Icons.download),
                          label: const Text('Download Video'),
                        ),
                    ]),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  _GiftStoryOutputDraft _giftStoryOutputFromRequest(
      Map<String, dynamic> request) {
    final status =
        '${request['giftStatus'] ?? request['status']}'.toLowerCase();
    return _GiftStoryOutputDraft(
      senderName: '${request['senderName'] ?? ''}',
      recipientName: '${request['recipientName'] ?? ''}',
      relationship: '${request['relationship'] ?? ''}',
      occasion: '${request['occasion'] ?? 'Gift'}',
      story: '${request['senderMessageText'] ?? request['notes'] ?? ''}',
      interests: _giftStringList(
          request['interestTags'] ?? request['interests'] ?? const []),
      audioUrl: '${request['giftStoryCustomAudioUrl'] ?? ''}'.trim().isEmpty
          ? null
          : '${request['giftStoryCustomAudioUrl']}',
      photoUrls: _giftStringList(
          request['giftStoryPhotos'] ?? request['approvedGiftPhotoUrls']),
      deliveryCompleted: status == 'delivered' || status == 'completed',
      renderedVideoUrl:
          '${request['giftStoryVideoUrl'] ?? request['giftStoryRenderedVideoUrl'] ?? ''}'
                  .trim()
                  .isEmpty
              ? null
              : '${request['giftStoryVideoUrl'] ?? request['giftStoryRenderedVideoUrl']}',
    );
  }

  Widget _giftConciergeFlow(_CircumColors colors, bool narrow) {
    final steps = [
      'Who',
      'Moment',
      'Story',
      'World',
      'Preview',
      'Details',
      'Review',
    ];
    return _GlassPanel(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < steps.length; i++)
                ChoiceChip(
                  label: Text('${i + 1}. ${steps[i]}'),
                  selected: _giftStep == i,
                  onSelected: (_) => setState(() => _giftStep = i),
                ),
            ],
          ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(
              key: ValueKey(_giftStep),
              child: switch (_giftStep) {
                0 => _giftStepCard(
                    colors: colors,
                    title: 'Who are we gifting?',
                    subtitle:
                        'Choose how this gift should arrive, then tell us who they are to you.',
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _giftOptionGrid(
                          colors,
                          _relationshipMoments.keys.toList(),
                          (label) => _giftMode == _relationshipMoments[label],
                          (label) => setState(() {
                            _giftMode =
                                _relationshipMoments[label] ?? _giftMode;
                            if (label == 'Myself') _relationship = 'Myself';
                            if (label == 'Anonymous Gift') {
                              _relationship = 'Anonymous Recipient';
                            }
                          }),
                        ),
                        const SizedBox(height: 18),
                        _giftGlassDropdown(
                          colors: colors,
                          label: _giftMode == 'gift_myself'
                              ? 'Relationship'
                              : 'Who is this person to you?',
                          value: _relationship,
                          options: _relationships,
                          onSelected: (value) =>
                              setState(() => _relationship = value),
                        ),
                        if (_giftMode == 'anonymous_gift') ...[
                          const SizedBox(height: 12),
                          _giftGlassDropdown(
                            colors: colors,
                            label: 'Anonymous gift type',
                            value: _anonymousGiftType,
                            options: const ['direct', 'campaign'],
                            labelFor: (value) => value == 'campaign'
                                ? 'Campaign · Bringing London Closer'
                                : 'Direct anonymous gift',
                            onSelected: (value) =>
                                setState(() => _anonymousGiftType = value),
                          ),
                          const SizedBox(height: 12),
                          _giftGlassDropdown(
                            colors: colors,
                            label: 'Identity reveal',
                            value: _senderRevealMode,
                            options: const [
                              'anonymous_forever',
                              'reveal_after_delivery',
                              'anonymous_until_consent',
                              'reveal_immediately',
                            ],
                            labelFor: (value) => switch (value) {
                              'anonymous_forever' => 'Anonymous forever',
                              'reveal_after_delivery' =>
                                'Reveal after delivery',
                              'anonymous_until_consent' =>
                                'Reveal only with later consent',
                              _ => 'Reveal immediately',
                            },
                            onSelected: (value) =>
                                setState(() => _senderRevealMode = value),
                          ),
                        ],
                        if (_giftMode == 'gift_myself') ...[
                          const SizedBox(height: 12),
                          _giftGlassDropdown(
                            colors: colors,
                            label: 'Self-gift frequency',
                            value: _selfGiftFrequency,
                            options: const [
                              'one_off',
                              'monthly',
                              'quarterly',
                              'custom',
                            ],
                            labelFor: (value) => switch (value) {
                              'one_off' => 'One-off',
                              'monthly' => 'Monthly',
                              'quarterly' => 'Quarterly',
                              _ => 'Custom',
                            },
                            onSelected: (value) =>
                                setState(() => _selfGiftFrequency = value),
                          ),
                        ],
                      ],
                    ),
                  ),
                1 => _giftStepCard(
                    colors: colors,
                    title: 'What moment are we creating?',
                    subtitle:
                        'Search the occasion list, then keep moving. This keeps the page calm and focused.',
                    body: _giftGlassDropdown(
                      colors: colors,
                      label: 'Occasion or moment',
                      value: _occasion,
                      options: _occasions,
                      onSelected: (value) => setState(() => _occasion = value),
                    ),
                  ),
                2 => _giftStepCard(
                    colors: colors,
                    title: _giftMode == 'gift_myself'
                        ? 'Tell me about yourself'
                        : 'Tell me about them',
                    subtitle:
                        'The better the story, the more personal the experience can feel.',
                    body: _giftStoryBriefingPanel(colors),
                  ),
                3 => _giftStepCard(
                    colors: colors,
                    title: 'Discover their world',
                    subtitle:
                        'Pick across categories. Selected interests stay visible here and travel into the same existing request field.',
                    body: _giftInterestSelector(colors),
                  ),
                4 => _giftStepCard(
                    colors: colors,
                    title: 'IRIS experience preview',
                    subtitle:
                        'A private direction of travel. Exact gifts, brands and suppliers stay hidden.',
                    body: _giftIrisPreview(colors),
                  ),
                5 => _giftStepCard(
                    colors: colors,
                    title: 'A few details to make it perfect',
                    subtitle:
                        'These are the same operational fields Circum already uses for payment, review and delivery.',
                    body: _giftDetailsFields(colors, narrow),
                  ),
                _ => _giftStepCard(
                    colors: colors,
                    title: 'One final step',
                    subtitle:
                        'Review the safe summary, then continue to Stripe. Gift contents remain private.',
                    body: _giftFinalStep(colors),
                  ),
              },
            ),
          ),
          const SizedBox(height: 18),
          _giftStepControls(colors),
        ],
      ),
    );
  }

  Widget _giftStepCard({
    required _CircumColors colors,
    required String title,
    required String subtitle,
    required Widget body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: colors.text,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(color: colors.mutedText, fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 18),
        body,
      ],
    );
  }

  Widget _giftOptionGrid(
    _CircumColors colors,
    List<String> labels,
    bool Function(String label) selected,
    void Function(String label) onTap,
  ) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 560;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: labels
            .map((label) => SizedBox(
                  width: compact
                      ? double.infinity
                      : (constraints.maxWidth - 20) / 3,
                  child: _giftOptionCard(
                    colors,
                    label,
                    selected(label),
                    () => onTap(label),
                  ),
                ))
            .toList(),
      );
    });
  }

  Widget _giftOptionCard(
      _CircumColors colors, String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: selected
                ? [
                    colors.adminAccent.withValues(alpha: 0.34),
                    colors.adminGlow.withValues(alpha: 0.18),
                    colors.field.withValues(alpha: 0.76),
                  ]
                : [
                    colors.field.withValues(alpha: 0.74),
                    colors.adminAccent.withValues(alpha: 0.08),
                  ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? colors.adminAccent.withValues(alpha: 0.78)
                : colors.border.withValues(alpha: 0.75),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.adminGlow.withValues(alpha: 0.22),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? colors.adminAccent : colors.mutedText,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _giftGlassDropdown({
    required _CircumColors colors,
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onSelected,
    String Function(String value)? labelFor,
  }) {
    final display = labelFor?.call(value) ?? value;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            colors.adminAccent.withValues(alpha: 0.16),
            colors.field.withValues(alpha: 0.72),
          ],
        ),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.22)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Autocomplete<String>(
        key: ValueKey('$label-$value'),
        initialValue: TextEditingValue(text: display),
        optionsBuilder: (text) {
          final query = text.text.trim().toLowerCase();
          final matches = options.where((option) {
            final optionLabel = labelFor?.call(option) ?? option;
            return query.isEmpty ||
                optionLabel.toLowerCase().contains(query) ||
                option.toLowerCase().contains(query);
          }).toList();
          return matches.take(12);
        },
        displayStringForOption: (option) => labelFor?.call(option) ?? option,
        onSelected: onSelected,
        fieldViewBuilder: (context, controller, focusNode, onSubmit) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            style: TextStyle(
              color: colors.text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              labelText: label,
              prefixIcon:
                  Icon(Icons.keyboard_arrow_down, color: colors.adminAccent),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onSubmitted: (_) => onSubmit(),
          );
        },
        optionsViewBuilder: (context, onOptionSelected, matches) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints:
                    const BoxConstraints(maxHeight: 280, maxWidth: 520),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: colors.panel.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: colors.adminAccent.withValues(alpha: 0.25)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 22,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shrinkWrap: true,
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final option = matches.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(labelFor?.call(option) ?? option,
                          style: TextStyle(
                              color: colors.text, fontWeight: FontWeight.w800)),
                      onTap: () => onOptionSelected(option),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _giftStoryBriefingPanel(_CircumColors colors) {
    final selfGift = _giftMode == 'gift_myself';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.adminAccent.withValues(alpha: 0.18),
            colors.adminGlow.withValues(alpha: 0.10),
            colors.field.withValues(alpha: 0.78),
          ],
        ),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: colors.adminGlow.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _notes,
            maxLines: 8,
            style: TextStyle(color: colors.text, fontSize: 18, height: 1.55),
            decoration: InputDecoration(
              labelText: selfGift ? 'What makes you special?' : null,
              labelStyle: TextStyle(
                color: colors.adminAccent.withValues(alpha: 0.92),
                fontWeight: FontWeight.w900,
              ),
              hintText: selfGift
                  ? 'Tell us what makes you smile, what you love, what you dislike, what you talk about, what you dream about, and anything that would help Circum create something thoughtful.'
                  : 'Tell us what makes them smile, what they love, what they dislike, what they talk about, what they dream about, and anything that would help Circum create something thoughtful.',
              hintStyle:
                  TextStyle(color: colors.mutedText, fontSize: 17, height: 1.5),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _giftBlueSection(
    _CircumColors colors, {
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            colors.adminAccent.withValues(alpha: 0.12),
            colors.field.withValues(alpha: 0.70),
          ],
        ),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.text,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _giftInterestSelector(_CircumColors colors) {
    final uncategorised = _interestOptions
        .where((interest) =>
            !_interestGroups.values.expand((group) => group).contains(interest))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: [
              colors.adminGlow.withValues(alpha: 0.16),
              colors.adminAccent.withValues(alpha: 0.12),
              colors.field.withValues(alpha: 0.72),
            ]),
            border:
                Border.all(color: colors.adminAccent.withValues(alpha: 0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Selected Interests',
                  style: TextStyle(
                      color: colors.text, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (_interests.isEmpty)
                Text('Choose interests below or add a personal one.',
                    style: TextStyle(color: colors.mutedText))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _interests
                      .map((interest) => InputChip(
                            label: Text(interest),
                            onDeleted: () =>
                                setState(() => _interests.remove(interest)),
                          ))
                      .toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _giftField(_customInterest, 'Add custom interest',
                  Icons.add_circle_outline),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Add custom interest',
              onPressed: () {
                final value = _customInterest.text.trim();
                if (value.isEmpty) return;
                setState(() {
                  _interests.add(value);
                  _customInterest.clear();
                });
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final entry in {
          ..._interestGroups,
          if (uncategorised.isNotEmpty) 'More interests': uncategorised,
        }.entries)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colors.adminAccent.withValues(alpha: 0.11),
                  colors.field.withValues(alpha: 0.74),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: colors.adminAccent.withValues(alpha: 0.18)),
            ),
            child: ExpansionTile(
              key: ValueKey(
                  '${entry.key}-${_expandedInterestGroups.contains(entry.key)}'),
              initiallyExpanded: _expandedInterestGroups.contains(entry.key),
              onExpansionChanged: (expanded) => setState(() {
                if (expanded) {
                  if (_expandedInterestGroups.length >= 2) {
                    _expandedInterestGroups.remove(
                      _expandedInterestGroups.first,
                    );
                  }
                  _expandedInterestGroups.add(entry.key);
                } else {
                  _expandedInterestGroups.remove(entry.key);
                }
              }),
              collapsedIconColor: colors.mutedText,
              iconColor: colors.adminAccent,
              title: Text(entry.key,
                  style: TextStyle(
                      color: colors.text, fontWeight: FontWeight.w900)),
              subtitle: Text('${entry.value.length} options',
                  style: TextStyle(color: colors.mutedText)),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: entry.value
                      .map((interest) => FilterChip(
                            label: Text(interest),
                            selected: _interests.contains(interest),
                            onSelected: (selected) => setState(() => selected
                                ? _interests.add(interest)
                                : _interests.remove(interest)),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _giftIrisPreview(_CircumColors colors) {
    final preview = buildGiftPreview();
    final signals = getGiftSignals();
    final directions = getExperienceDirections();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            colors.adminAccent.withValues(alpha: 0.20),
            colors.adminGlow.withValues(alpha: 0.10),
            colors.field.withValues(alpha: 0.65),
          ],
        ),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.auto_awesome, color: colors.adminAccent),
            const SizedBox(width: 10),
            Text('IRIS Experience Preview',
                style: TextStyle(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 12),
          Text(
            preview,
            style: TextStyle(color: colors.text, fontSize: 18, height: 1.45),
          ),
          const SizedBox(height: 14),
          Text('Signals detected',
              style:
                  TextStyle(color: colors.text, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: signals
                .map((tag) => Chip(
                      label: Text(tag),
                      backgroundColor: colors.panel.withValues(alpha: 0.62),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          Text('Experience direction',
              style:
                  TextStyle(color: colors.text, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                directions.map((tag) => _giftLuxuryChip(colors, tag)).toList(),
          ),
          const SizedBox(height: 14),
          Text(
            'Exact gift items, brands, suppliers, retailers, and procurement costs stay hidden before delivery.',
            style: TextStyle(color: colors.mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String buildGiftPreview() {
    final interests = _interests.take(3).toList();
    final interestText = interests.isEmpty
        ? 'the story you have shared'
        : interests.map((value) => value.toLowerCase()).join(', ');
    final directions = getExperienceDirections();
    final budget = double.tryParse(_budget.text.trim());
    final timing = _deliveryDate == null
        ? ''
        : ' with ${_timeWindow.toLowerCase()} delivery in mind';
    final storySignal = _notes.text.trim().length > 24
        ? ' and the personal details in their story'
        : '';
    final target = _giftMode == 'gift_myself'
        ? 'yourself'
        : 'a ${_relationship.toLowerCase()}';
    return 'For $target celebrating ${_occasion.toLowerCase()} with interests in $interestText$storySignal, IRIS is shaping an experience around ${directions.take(3).map((value) => value.toLowerCase()).join(', ')}${budget == null ? '' : ' within a £${budget.toStringAsFixed(0)} budget'}$timing.';
  }

  List<String> getGiftSignals() {
    final signals = <String>[_relationship, _occasion, ..._interests.take(4)];
    final budget = double.tryParse(_budget.text.trim());
    if (budget != null) signals.add('£${budget.toStringAsFixed(0)} budget');
    if (_deliveryDate != null) signals.add(_timeWindow);
    return signals.toSet().toList();
  }

  List<String> getExperienceDirections() {
    final tags = <String>{'Thoughtful'};
    if (_interests
        .any(['Fine Dining', 'Jewellery', 'Architecture', 'Luxury'].contains))
      tags.add('Elegant');
    if (_relationship == 'Partner' || _occasion == 'Anniversary') {
      tags.add('Intimate');
    }
    if (_occasion == 'Get Well Soon' ||
        _interests.contains('Spa Experiences') ||
        _interests.contains('Wellness Retreats')) tags.add('Restorative');
    if (_interests.contains('Gaming') || _interests.contains('Festivals')) {
      tags.add('Playful');
    }
    if (_interests.any(['Travel', 'Aviation', 'Adventure Travel'].contains)) {
      tags.add('Adventure-led');
    }
    if (_interests
        .any(['Christian', 'Muslim', 'Jewish', 'Spiritual'].contains)) {
      tags.add('Faith-inspired');
    }
    if (_interests.any(['Art', 'Design', 'Writing', 'Music'].contains)) {
      tags.add('Creative');
    }
    if (_occasion == 'Get Well Soon' || _occasion == 'Sympathy') {
      tags.add('Comforting');
    }
    if (_budget.text.isNotEmpty) tags.add('Premium');
    return tags.toList();
  }

  Widget _giftDetailsFields(_CircumColors colors, bool narrow) {
    final fieldWidth = narrow ? double.infinity : 300.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _giftBlueSection(
          colors,
          title: 'Sender',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: fieldWidth,
                child: _giftField(
                    _senderName, 'Sender name', Icons.person_outline),
              ),
              SizedBox(
                width: fieldWidth,
                child: _giftField(
                    _senderEmail, 'Sender email', Icons.email_outlined,
                    type: TextInputType.emailAddress),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _giftBlueSection(
          colors,
          title: 'Recipient',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: fieldWidth,
                child: _giftField(
                    _recipientName, 'Recipient name', Icons.redeem_outlined),
              ),
              SizedBox(
                width: fieldWidth,
                child: _giftField(_recipientPhone, 'Recipient phone',
                    Icons.contact_phone_outlined),
              ),
              SizedBox(
                width: fieldWidth,
                child: _giftField(
                    _recipientEmail, 'Recipient email', Icons.email_outlined,
                    type: TextInputType.emailAddress),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: narrow ? double.infinity : 260,
              child: _giftGlassDropdown(
                colors: colors,
                label: 'Relationship',
                value: _relationship,
                options: _relationships,
                onSelected: (value) => setState(() => _relationship = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _AddressField(
          colors: colors,
          icon: Icons.location_on_outlined,
          label: 'Delivery address',
          controller: _deliveryAddress,
          verified: _validatedGiftAddress?.isVerified == true,
          onSelected: (address) =>
              setState(() => _validatedGiftAddress = address),
          onEdited: (_) => setState(() => _validatedGiftAddress = null),
          verifiedMessage: 'Verified delivery address selected',
          glassStyle: true,
          enableFreeLookup: true,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: narrow ? double.infinity : 260,
              child: _giftGlassActionPill(
                colors: colors,
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: _deliveryDate ??
                        DateTime.now().add(const Duration(days: 2)),
                  );
                  if (date != null) setState(() => _deliveryDate = date);
                },
                icon: const Icon(Icons.calendar_month),
                label: Text(_deliveryDate == null
                    ? 'Preferred delivery date'
                    : _adminDateText(_deliveryDate)),
              ),
            ),
            SizedBox(
              width: narrow ? double.infinity : 260,
              child: _giftGlassDropdown(
                colors: colors,
                label: 'Time window',
                value: _timeWindow,
                options: const ['Morning', 'Afternoon', 'Evening'],
                onSelected: (value) => setState(() => _timeWindow = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [50, 100, 250, 500, 1000, 1500]
              .map((value) => _giftBudgetChip(colors, value))
              .toList(),
        ),
        const SizedBox(height: 8),
        _giftField(
            _budget, 'Gift budget (minimum £50)', Icons.payments_outlined,
            type: const TextInputType.numberWithOptions(decimal: true)),
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
              width: narrow ? double.infinity : 180,
              child:
                  _giftField(_clothingSize, 'Clothing size', Icons.checkroom)),
          SizedBox(
              width: narrow ? double.infinity : 180,
              child: _giftField(_shoeSize, 'Shoe size', Icons.hiking)),
          SizedBox(
              width: narrow ? double.infinity : 180,
              child: _giftField(_ringSize, 'Ring size', Icons.circle_outlined)),
          SizedBox(
              width: narrow ? double.infinity : 180,
              child: _giftField(_height, 'Height', Icons.height)),
        ]),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: narrow ? double.infinity : 260,
              child: _giftGlassDropdown(
                colors: colors,
                label: 'Preferred fit',
                value: _preferredFit,
                options: const ['Slim', 'Regular', 'Relaxed', 'Oversized'],
                onSelected: (value) => setState(() => _preferredFit = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _giftField(
            _favouriteColours, 'Favourite colours', Icons.palette_outlined),
        _giftField(_likedBrands, 'Brands they like', Icons.favorite_border),
        _giftField(_dislikedBrands, 'Brands they dislike', Icons.block),
        _giftField(
            _personalMessage, 'Personal message', Icons.chat_bubble_outline,
            lines: 3),
        _giftField(
            _notes,
            'Allergies, sensitivities, dietary restrictions and additional notes',
            Icons.health_and_safety_outlined,
            lines: 4),
        Text(
          'Include medical conditions, religious considerations, accessibility needs, dislikes, special requests, or anything Circum should avoid.',
          style: TextStyle(color: colors.mutedText, fontSize: 12),
        ),
        const SizedBox(height: 12),
        _giftGlassActionPill(
          colors: colors,
          onPressed: _pickPhoto,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(_photo == null
              ? 'Add optional recipient photo'
              : 'Photo selected · Replace'),
        ),
        if (_photo != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _photo = null),
              icon: const Icon(Icons.close),
              label: const Text('Remove photo'),
            ),
          ),
      ],
    );
  }

  Widget _giftFinalStep(_CircumColors colors) {
    final grossBudget = double.tryParse(_budget.text.trim());
    final budgetText =
        grossBudget == null ? 'Not set' : '£${grossBudget.toStringAsFixed(0)}';
    final recipientName = _recipientName.text.trim().isEmpty
        ? 'Recipient'
        : _recipientName.text.trim();
    final address = _deliveryAddress.text.trim().isEmpty
        ? 'Destination not provided yet'
        : _deliveryAddress.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xff07111f).withValues(alpha: 0.94),
                  colors.adminAccent.withValues(alpha: 0.24),
                  const Color(0xff241246).withValues(alpha: 0.90),
                  colors.field.withValues(alpha: 0.78),
                ],
              ),
              border: Border.all(
                color: colors.adminAccent.withValues(alpha: 0.36),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.adminGlow.withValues(alpha: 0.30),
                  blurRadius: 46,
                  spreadRadius: 2,
                  offset: const Offset(0, 24),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.36),
                  blurRadius: 36,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.08),
                  Colors.transparent,
                  colors.adminGlow.withValues(alpha: 0.08),
                ],
                stops: const [0, 0.42, 1],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GIFT EXPERIENCE SUMMARY',
                            style: TextStyle(
                              color: colors.adminAccent,
                              fontSize: 12,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Prepared for review before gifting',
                            style: TextStyle(
                                color: colors.mutedText,
                                fontSize: 14,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.auto_awesome,
                        color: colors.adminAccent, size: 30),
                  ],
                ),
                const SizedBox(height: 30),
                _giftIrisUnderstandingCard(colors),
                const SizedBox(height: 18),
                _giftRecipientHero(colors, recipientName),
                const SizedBox(height: 22),
                _giftLuxuryInfoGrid(colors, budgetText, address),
                const SizedBox(height: 18),
                _giftConfidentialityCard(colors),
                const SizedBox(height: 16),
                _giftPromiseMiniPanel(colors),
                const SizedBox(height: 18),
                _giftPaymentSummaryPanel(colors, budgetText),
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  Text(_message!,
                      style: TextStyle(
                          color: colors.text, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      colors: [
                        colors.adminAccent.withValues(alpha: 0.96),
                        colors.adminGlow.withValues(alpha: 0.86),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.adminGlow.withValues(alpha: 0.34),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      )
                    ],
                  ),
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.diamond_outlined),
                    label: Text(_saving
                        ? 'Preparing payment...'
                        : 'Gift This Experience'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'The exact gift contents, supplier costs, and internal fulfilment plan remain private until delivery.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.mutedText, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  'Circum may ask to record or share a gift reaction. This is optional, and the gift can still be received if filming or public posting is declined.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _giftIrisUnderstandingCard(_CircumColors colors) {
    final insight = _giftIrisUnderstanding();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.adminGlow.withValues(alpha: 0.22),
            colors.adminAccent.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.07),
            Colors.black.withValues(alpha: 0.18),
          ],
        ),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.26)),
        boxShadow: [
          BoxShadow(
            color: colors.adminGlow.withValues(alpha: 0.22),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: colors.adminAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'What IRIS Understands',
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            insight,
            style: TextStyle(
              color: colors.text,
              fontSize: 17,
              height: 1.48,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _giftIrisUnderstanding() {
    final clues = [
      _relationship,
      _occasion,
      _interests.join(' '),
      _personalMessage.text,
      _notes.text,
      _favouriteColours.text,
      _likedBrands.text,
      _dislikedBrands.text,
    ].where((value) => value.trim().isNotEmpty).join(' ').toLowerCase();
    final meaningfulInput = _interests.isNotEmpty ||
        _personalMessage.text.trim().length > 18 ||
        _notes.text.trim().length > 18 ||
        _favouriteColours.text.trim().isNotEmpty ||
        _likedBrands.text.trim().isNotEmpty;
    if (!meaningfulInput) {
      return 'IRIS has enough to begin preparing a thoughtful gift experience.\n\nAs more details are added, IRIS can better understand the feeling the gift should carry.\n\nIRIS will keep this in mind as the gift experience is prepared.';
    }

    bool hasAny(Iterable<String> terms) =>
        terms.any((term) => clues.contains(term.toLowerCase()));

    if (hasAny([
      'sports',
      'sport',
      'football',
      'arsenal',
      'live game',
      'gym',
      'fitness',
      'running',
      'cycling',
    ])) {
      return 'They appear to enjoy excitement, shared experiences and the anticipation that comes with special occasions.\n\nSport is more than entertainment to them — it is part of their identity and a source of lasting memories.\n\nIRIS will keep this in mind as the gift experience is prepared.';
    }
    if (hasAny([
      'pink',
      'beauty',
      'makeup',
      'fashion',
      'self-care',
      'self care',
      'skincare',
      'jewellery',
      'fragrance',
    ])) {
      return 'They appear to enjoy self-expression, personal style and thoughtful details that feel made for them.\n\nA gift experience with warmth, elegance and a sense of care may feel especially meaningful.\n\nIRIS will keep this in mind as the gift experience is prepared.';
    }
    if (hasAny([
      'yellow',
      'nature',
      'calm',
      'books',
      'book',
      'tea',
      'gardening',
      'wellness',
      'minimalist',
    ])) {
      return 'They may value warmth, calm and simple moments that feel peaceful rather than overwhelming.\n\nA gift experience that feels gentle, personal and comforting may resonate with them.\n\nIRIS will keep this in mind as the gift experience is prepared.';
    }
    if (hasAny([
      'red',
      'cars',
      'car',
      'boxing',
      'adventure',
      'nightlife',
      'motorcycles',
      'travel',
      'festivals',
    ])) {
      return 'They seem drawn to energy, intensity and experiences with a sense of excitement.\n\nA gift experience with confidence, movement and memorable impact may suit their personality.\n\nIRIS will keep this in mind as the gift experience is prepared.';
    }
    if (hasAny([
      'partner',
      'husband',
      'wife',
      'fiancé',
      'fiancée',
      'anniversary',
      'valentine'
    ])) {
      return 'They may value intimacy, attention and details that feel personal rather than generic.\n\nA gift experience with warmth, closeness and a sense of occasion may feel especially meaningful.\n\nIRIS will keep this in mind as the gift experience is prepared.';
    }

    return 'They appear to value thoughtful details, personal attention and a gift experience that feels considered rather than generic.\n\nIRIS will keep this in mind as the gift experience is prepared.';
  }

  Widget _giftRecipientHero(_CircumColors colors, String recipientName) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.10),
            colors.adminAccent.withValues(alpha: 0.10),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prepared For',
            style: TextStyle(
              color: colors.mutedText,
              fontSize: 13,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            recipientName.toUpperCase(),
            style: TextStyle(
              color: colors.text,
              fontSize: 44,
              height: 0.96,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _giftLuxuryChip(colors, _relationship),
              _giftLuxuryChip(colors, _occasion),
            ],
          ),
        ],
      ),
    );
  }

  Widget _giftLuxuryInfoGrid(
      _CircumColors colors, String budgetText, String address) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 640;
      final itemWidth =
          compact ? double.infinity : (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
              width: itemWidth,
              child: _giftLuxuryInfoBlock(
                  colors, 'Experience Budget', budgetText)),
          SizedBox(
              width: itemWidth,
              child: _giftLuxuryInfoBlock(colors, 'Delivery Window',
                  '${_adminDateText(_deliveryDate)} • $_timeWindow')),
          SizedBox(
              width: double.infinity,
              child: _giftLuxuryInfoBlock(colors, 'Destination', address,
                  maxLines: 4)),
        ],
      );
    });
  }

  Widget _giftLuxuryInfoBlock(_CircumColors colors, String label, String value,
      {int maxLines = 2}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.black.withValues(alpha: 0.18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            value.isEmpty ? 'Not provided yet' : value,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: colors.text,
                fontSize: 22,
                height: 1.15,
                fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _giftConfidentialityCard(_CircumColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            colors.adminAccent.withValues(alpha: 0.16),
            Colors.black.withValues(alpha: 0.18),
          ],
        ),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: colors.adminAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gift Contents Remain Confidential',
                    style: TextStyle(
                        color: colors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  'Circum does not reveal products, brands, suppliers, basket contents or fulfilment selections before delivery.\n\nOnly the final recipient experiences the surprise.',
                  style: TextStyle(color: colors.mutedText, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _giftPromiseMiniPanel(_CircumColors colors) {
    const promises = [
      'Thoughtfully Curated',
      'Reviewed By The Gifts Team',
      'Delivered By Circum',
      'Built Around Your Story',
      'Designed To Surprise',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: promises
            .map((promise) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle,
                        color: colors.adminAccent, size: 18),
                    const SizedBox(width: 8),
                    Text(promise,
                        style: TextStyle(
                            color: colors.text, fontWeight: FontWeight.w800)),
                  ],
                ))
            .toList(),
      ),
    );
  }

  Widget _giftPaymentSummaryPanel(_CircumColors colors, String budgetText) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            colors.adminGlow.withValues(alpha: 0.18),
            colors.adminAccent.withValues(alpha: 0.12),
            Colors.black.withValues(alpha: 0.22),
          ],
        ),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total Experience Budget',
              style: TextStyle(
                  color: colors.mutedText,
                  fontSize: 13,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            budgetText,
            style: TextStyle(
                color: colors.text,
                fontSize: 40,
                height: 1,
                fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Text(
            'Nothing is confirmed until our team reviews and approves your gift.',
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Payment is held securely via Stripe and released only upon team approval.',
            style: TextStyle(color: colors.mutedText),
          ),
        ],
      ),
    );
  }

  Widget _giftLuxuryChip(_CircumColors colors, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            colors.adminAccent.withValues(alpha: 0.28),
            colors.adminGlow.withValues(alpha: 0.16),
          ],
        ),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.28)),
      ),
      child: Text(label,
          style: TextStyle(color: colors.text, fontWeight: FontWeight.w900)),
    );
  }

  Widget _giftReviewPanel(
    _CircumColors colors, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    BoxDecoration? decoration,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: padding,
      decoration: decoration ??
          BoxDecoration(
            color: colors.field.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.border.withValues(alpha: 0.82)),
          ),
      child: child,
    );
  }

  Widget _giftReviewHeading(_CircumColors colors, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: colors.adminAccent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: colors.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _giftReviewStat(_CircumColors colors, String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 170),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.panel.withValues(alpha: 0.54),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: colors.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(value.isEmpty ? 'Not provided yet' : value,
                style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  List<String> _giftStoryHighlights() {
    final raw = _notes.text.trim();
    if (raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'[.!?\n]+'))
        .map((line) => line.trim())
        .where((line) => line.length >= 18)
        .take(3)
        .toList();
  }

  Widget _giftSummaryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w900))),
          Expanded(child: Text(value.isEmpty ? 'Not provided yet' : value)),
        ],
      ),
    );
  }

  Widget _giftStepControls(_CircumColors colors) {
    return Row(
      children: [
        if (_giftStep > 0)
          TextButton.icon(
            onPressed: () => setState(() => _giftStep--),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        const Spacer(),
        if (_giftStep < 6)
          FilledButton.icon(
            onPressed: () => setState(() => _giftStep++),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
      ],
    );
  }

  Widget _giftGlassActionPill({
    required _CircumColors colors,
    required VoidCallback? onPressed,
    required Widget icon,
    required Widget label,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            colors.adminAccent.withValues(alpha: 0.16),
            colors.field.withValues(alpha: 0.76),
          ],
        ),
        border: Border.all(color: colors.adminAccent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: colors.adminGlow.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: label,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: colors.text,
          minimumSize: const Size(0, 58),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          side: BorderSide.none,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _giftBudgetChip(_CircumColors colors, int value) {
    final selected = _budget.text == '$value';
    return ChoiceChip(
      label: Text('£$value'),
      selected: selected,
      onSelected: (_) => setState(() => _budget.text = '$value'),
      labelStyle: TextStyle(
        color: selected ? colors.text : colors.text.withValues(alpha: 0.88),
        fontWeight: FontWeight.w900,
      ),
      selectedColor: colors.adminAccent.withValues(alpha: 0.30),
      backgroundColor: colors.field.withValues(alpha: 0.76),
      side: BorderSide(
        color: selected
            ? colors.adminAccent.withValues(alpha: 0.58)
            : colors.adminAccent.withValues(alpha: 0.20),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _giftField(
      TextEditingController controller, String label, IconData icon,
      {TextInputType? type, int lines = 1, bool obscure = false}) {
    final colors = widget.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        constraints: BoxConstraints(minHeight: lines > 1 ? 120 : 58),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(lines > 1 ? 24 : 22),
          gradient: LinearGradient(
            colors: [
              colors.adminAccent.withValues(alpha: 0.16),
              colors.field.withValues(alpha: 0.76),
            ],
          ),
          border: Border.all(color: colors.adminAccent.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: colors.adminGlow.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TextField(
          controller: controller,
          keyboardType: type,
          maxLines: lines,
          obscureText: obscure,
          style: TextStyle(
            color: colors.text,
            fontSize: lines > 1 ? 16 : 15,
            height: 1.45,
            fontWeight: FontWeight.w800,
          ),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: colors.adminAccent, size: 20),
            labelStyle:
                TextStyle(color: colors.mutedText, fontWeight: FontWeight.w700),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

class _GiftStoryViewer extends StatefulWidget {
  final _CircumColors colors;
  final Map<String, dynamic> gift;
  final VoidCallback onClose;
  final bool adminPreview;

  const _GiftStoryViewer({
    required this.colors,
    required this.gift,
    required this.onClose,
    this.adminPreview = false,
  });

  @override
  State<_GiftStoryViewer> createState() => _GiftStoryViewerState();
}

class _GiftStoryViewerState extends State<_GiftStoryViewer> {
  static const _chapterDurationMs = 8000.0;
  int _chapter = 0;
  int _transitionDirection = 1;
  double _chapterProgress = 0;
  int? _progressFrame;
  num? _progressStartedAt;
  late bool _musicEnabled;
  late bool _muted;
  late bool _playing;
  late String _sharePrivacy;
  html.AudioElement? _audio;
  String? _musicPrompt;
  bool _exportingVideo = false;
  double _exportProgress = 0;
  bool _storyPlayRecorded = false;
  bool _storyCompletionRecorded = false;

  @override
  void initState() {
    super.initState();
    _musicEnabled = widget.gift['giftStoryMusicEnabled'] == true &&
        '${widget.gift['giftStoryCustomAudioUrl'] ?? ''}'.trim().isNotEmpty;
    _muted = false;
    _playing = false;
    _sharePrivacy =
        _giftStorySharePrivacy('${widget.gift['giftStorySharePrivacy'] ?? ''}');
    _markRevealViewed();
    _restartChapterProgress();
  }

  @override
  void dispose() {
    if (_progressFrame != null) {
      html.window.cancelAnimationFrame(_progressFrame!);
    }
    _audio?.pause();
    _audio = null;
    super.dispose();
  }

  Future<void> _markRevealViewed() async {
    if (widget.adminPreview) return;
    final id = '${widget.gift['id'] ?? ''}';
    if (id.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('giftRequests').doc(id).set({
        'giftStoryRevealViewedAt': FieldValue.serverTimestamp(),
        'giftStoryUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Gift Story viewed update failed: $error');
    }
  }

  List<_GiftStoryChapter> get _chapters {
    final gift = widget.gift;
    final interests = _giftList(gift['interestTags']).isNotEmpty
        ? _giftList(gift['interestTags'])
        : _giftList(gift['interests']);
    final revealItems = _giftRevealItems(gift);
    final photoUrls = <String>{
      ..._giftStringList(gift['giftStoryPhotos']),
      ..._giftStringList(gift['giftStoryPhotoUrls']),
    }.toList();
    final senderMessage =
        '${gift['senderMessageText'] ?? gift['personalMessage'] ?? ''}'.trim();
    final circumMessage = '${gift['giftStoryCircumMessage'] ?? ''}'.trim();
    final voice = gift['voiceNote'] is Map
        ? Map<String, dynamic>.from(gift['voiceNote'] as Map)
        : const <String, dynamic>{};
    final senderVoiceNoteUrl =
        '${gift['giftStorySenderVoiceNoteUrl'] ?? voice['downloadUrl'] ?? voice['url'] ?? gift['voiceNoteUrl'] ?? ''}'
            .trim();
    final senderVoiceDuration =
        _giftStoryIntFromDynamic(voice['durationSeconds']);
    final chapters = [
      _GiftStoryChapter(
        icon: Icons.card_giftcard,
        title: 'Your gift is en route',
        body: 'Someone wanted this moment to feel special.',
        chips: const ['PREPARED BY GIFTS BY CIRCUM'],
        photoUrl: photoUrls.isEmpty ? null : photoUrls.first,
      ),
      _GiftStoryChapter(
        icon: Icons.message_outlined,
        title: 'A message for you',
        body: senderMessage.isEmpty
            ? 'This gift was designed around what makes you smile.'
            : senderMessage,
        chips: const ['FROM SOMEONE WHO THOUGHT OF YOU'],
      ),
      if (senderVoiceNoteUrl.isNotEmpty)
        _GiftStoryChapter(
          icon: Icons.record_voice_over_outlined,
          title: 'A voice note was left for you',
          body: 'Listen to the sender’s original message.',
          chips: const ['Sender voice note'],
          audioUrl: senderVoiceNoteUrl,
          audioDurationSeconds: senderVoiceDuration,
        ),
      _GiftStoryChapter(
        icon: Icons.celebration,
        title: '${gift['occasion'] ?? 'A special moment'}',
        body:
            '${gift['recipientName'] ?? 'Recipient'} · ${_adminDateText(gift['deliveryDate'])}',
        chips: [
          'Thoughtful gifting',
          '${gift['deliveryTimeWindow'] ?? 'Delivered'}'
        ],
        photoUrl: photoUrls.length > 1 ? photoUrls[1] : null,
      ),
      _GiftStoryChapter(
        icon: Icons.auto_awesome,
        title: 'Why this was chosen',
        body: _giftStoryWhyText(gift, interests),
        chips: interests.take(6).toList(),
        photoUrl: photoUrls.length > 2 ? photoUrls[2] : null,
      ),
      _GiftStoryChapter(
        icon: Icons.diamond_outlined,
        title: 'The reveal',
        body: revealItems.length == 1
            ? revealItems.first
            : 'Each part of the experience was prepared to feel personal, thoughtful and memorable.',
        chips: revealItems.take(5).toList(),
        photoUrl: photoUrls.length > 3 ? photoUrls[3] : null,
      ),
      for (var i = 4; i < photoUrls.length; i++)
        _GiftStoryChapter(
          icon: Icons.photo_camera_back_outlined,
          title: 'A closer look',
          body:
              'Every detail was prepared to feel personal, thoughtful and memorable.',
          chips: const ['Gift detail'],
          photoUrl: photoUrls[i],
        ),
      const _GiftStoryChapter(
        icon: Icons.wallet_giftcard,
        title: 'Circum Gift Card',
        body:
            'If a physical Circum Gift Card was included, it can be redeemed through a Circum account.',
        chips: ['Redeem through Circum'],
      ),
      if (circumMessage.isNotEmpty)
        _GiftStoryChapter(
          icon: Icons.favorite_border,
          title: 'Message from Circum',
          body: circumMessage,
          chips: const ['Thoughtful gifting, delivered by Circum.'],
        ),
      const _GiftStoryChapter(
        icon: Icons.ios_share,
        title: 'Thank you for sharing this moment.',
        body: 'Gifted by Circum. Thoughtful gifting, delivered by Circum.',
        chips: ['Share My Gift Story'],
        finalChapter: true,
      ),
    ];
    return chapters.take(10).toList(growable: false);
  }

  void _restartChapterProgress() {
    if (_progressFrame != null) {
      html.window.cancelAnimationFrame(_progressFrame!);
    }
    _progressStartedAt = null;
    if (mounted) setState(() => _chapterProgress = 0);
    _progressFrame = html.window.requestAnimationFrame(_tickChapterProgress);
  }

  void _tickChapterProgress(num timestamp) {
    if (!mounted) return;
    _progressStartedAt ??= timestamp;
    final progress =
        ((timestamp - _progressStartedAt!) / _chapterDurationMs).clamp(0, 1);
    setState(() => _chapterProgress = progress.toDouble());
    if (progress >= 1) {
      if (_chapter < _chapters.length - 1) {
        _next();
      }
      return;
    }
    _progressFrame = html.window.requestAnimationFrame(_tickChapterProgress);
  }

  static List<String> _giftList(dynamic value) {
    if (value is Iterable) {
      return value
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static List<String> _giftRevealItems(Map<String, dynamic> gift) {
    final raw =
        '${gift['giftItemsSummary'] ?? gift['procurementItemTitle'] ?? gift['manualGiftPlan'] ?? ''}';
    final items = raw
        .split(RegExp(r'[\n,;]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(6)
        .toList();
    return items.isEmpty
        ? const ['A thoughtful surprise prepared by Circum']
        : items;
  }

  static String _giftStoryWhyText(
      Map<String, dynamic> gift, List<String> interests) {
    final focus =
        interests.isEmpty ? 'their story' : interests.take(3).join(', ');
    return 'This gift was designed around what makes them smile.\n\nIRIS and the Gifts Team considered $focus, the occasion, and the details shared before preparing the experience.';
  }

  void _next() {
    final next = math.min(_chapter + 1, _chapters.length - 1);
    setState(() {
      _transitionDirection = 1;
      _chapter = next;
    });
    _restartChapterProgress();
    if (!_storyPlayRecorded) {
      _storyPlayRecorded = true;
      unawaited(_recordStoryEvent('play'));
    }
    if (next == _chapters.length - 1 && !_storyCompletionRecorded) {
      _storyCompletionRecorded = true;
      unawaited(_recordStoryEvent('complete'));
    }
  }

  void _previous() {
    setState(() {
      _transitionDirection = -1;
      _chapter = math.max(_chapter - 1, 0);
    });
    _restartChapterProgress();
  }

  Future<void> _downloadCurrentSlide() async {
    const width = 720;
    const height = 1280;
    final canvas = html.CanvasElement(width: width, height: height);
    final photos = await _loadStoryExportPhotos();
    final chapter = _chapters[_chapter];
    _paintStoryVideoFrame(
      canvas.context2D,
      chapter,
      _chapter,
      _chapters.length,
      1,
      photos[chapter.photoUrl],
    );
    final blob = await canvas.toBlob('image/png');
    final id = '${widget.gift['id'] ?? 'story'}'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = 'circum-gift-story-$id-slide-${_chapter + 1}.png'
      ..click();
    Future<void>.delayed(
      const Duration(seconds: 2),
      () => html.Url.revokeObjectUrl(url),
    );
  }

  String get _storyLink {
    final token = _storyAccessToken;
    if (token.isNotEmpty) {
      return 'https://circumuk.com/story/${Uri.encodeComponent(token)}';
    }
    final id = '${widget.gift['id'] ?? ''}';
    return 'https://circumuk.com/?app=gifts&giftStory=$id';
  }

  String get _storyAccessToken =>
      '${widget.gift['giftStoryAccessToken'] ?? Uri.base.queryParameters['giftStoryToken'] ?? ''}'
          .trim();

  Future<void> _recordStoryEvent(String event) async {
    final token = _storyAccessToken;
    if (token.isEmpty || widget.adminPreview) return;
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('recordGiftStoryEvent')
          .call({'token': token, 'event': event});
    } catch (error) {
      debugPrint('Gift Story analytics event failed: $event ($error)');
    }
  }

  Future<void> _copyStoryLink() async {
    await Clipboard.setData(ClipboardData(text: _storyLink));
    unawaited(_recordStoryEvent('share'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gift Story link copied.')),
    );
  }

  Future<void> _shareStory() async {
    final encodedText = Uri.encodeComponent(_shareMessage);
    final opened = await launchUrl(
      Uri.parse('https://wa.me/?text=$encodedText'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) await _copyStoryLink();
  }

  String get _shareTitle => 'A special gift story awaits.';

  String get _shareMessage =>
      'A special gift story awaits.\n\nCreated with Gifts by Circum.\n$_storyLink';

  Future<void> _launchStoryShare(String platform) async {
    final url = Uri.encodeComponent(_storyLink);
    final text = Uri.encodeComponent(_shareMessage);
    final title = Uri.encodeComponent(_shareTitle);
    Uri? target;
    switch (platform) {
      case 'WhatsApp':
        target = Uri.parse('https://wa.me/?text=$text');
      case 'Facebook':
      case 'Facebook Story':
        target = Uri.parse('https://www.facebook.com/sharer/sharer.php?u=$url');
      case 'X':
        target = Uri.parse('https://twitter.com/intent/tweet?text=$text');
      case 'Messages':
        target = Uri.parse('sms:?&body=$text');
      case 'Email':
        target = Uri.parse('mailto:?subject=$title&body=$text');
      case 'Instagram Story':
      case 'Instagram DM':
      case 'Instagram':
      case 'TikTok':
      case 'Snapchat':
        await _exportStoryVideo(
          shareAfter: true,
          notice:
              '$platform will open through your device share sheet when supported.',
        );
        return;
    }
    if (target == null) return;
    final opened =
        await launchUrl(target, mode: LaunchMode.externalApplication);
    if (!opened) await _copyStoryLink();
  }

  Future<void> _updateSharePrivacy(String privacy) async {
    final next = _giftStorySharePrivacy(privacy);
    setState(() => _sharePrivacy = next);
    final id = '${widget.gift['id'] ?? ''}';
    if (id.isEmpty || widget.adminPreview) return;
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('updateGiftStoryPrivacy')
          .call({
        'giftRequestId': id,
        'token': _storyAccessToken,
        'privacy': next,
      });
    } catch (error) {
      debugPrint('Gift Story privacy update failed: $error');
    }
  }

  Future<void> _exportStoryVideo({
    bool shareAfter = false,
    String? notice,
  }) async {
    if (_exportingVideo) return;
    setState(() {
      _exportingVideo = true;
      _exportProgress = 0;
    });
    try {
      final result = await _loadStoredStoryVideo() ?? await _renderStoryVideo();
      if ('${widget.gift['giftStoryVideoStatus'] ?? ''}' != 'ready') {
        try {
          await _persistRenderedStoryVideo(result);
        } catch (error) {
          debugPrint(
              'Gift Story temporary video storage failed; local export continues: $error');
        }
      }
      final id = '${widget.gift['id'] ?? 'story'}'
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
      final filename = 'circum-gift-story-$id.${result.extension}';
      if (shareAfter) {
        final file = html.File([result.blob], filename, {'type': result.mime});
        try {
          await html.window.navigator.share({
            'title': _shareTitle,
            'text': 'Created with Gifts by Circum.',
            'files': [file],
          });
          unawaited(_recordStoryEvent('share'));
        } catch (error) {
          _downloadVideoBlob(result.blob, filename);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Video downloaded. Choose it from the social app to share.'),
              ),
            );
          }
        }
      } else {
        _downloadVideoBlob(result.blob, filename);
        unawaited(_recordStoryEvent('download'));
      }
      if (mounted && notice != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(notice)));
      }
    } catch (error) {
      debugPrint('Gift Story video export failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video export failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _exportingVideo = false;
          _exportProgress = 0;
        });
      }
    }
  }

  void _downloadVideoBlob(html.Blob blob, String filename) {
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = filename
      ..click();
    Future<void>.delayed(
      const Duration(seconds: 2),
      () => html.Url.revokeObjectUrl(url),
    );
  }

  Future<_GiftStoryVideoResult?> _loadStoredStoryVideo() async {
    if ('${widget.gift['giftStoryVideoStatus'] ?? ''}' != 'ready') return null;
    final giftId = '${widget.gift['id'] ?? ''}'.trim();
    if (giftId.isEmpty) return null;
    try {
      final response =
          await FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('getGiftStoryVideoDownload')
              .call({
        'giftRequestId': giftId,
        'token': _storyAccessToken,
      });
      final payload = Map<String, dynamic>.from(response.data as Map);
      final mime = '${payload['mime'] ?? 'video/webm'}';
      final request = await html.HttpRequest.request(
        '${payload['downloadUrl']}',
        responseType: 'blob',
      );
      final blob = request.response as html.Blob?;
      if (blob == null || blob.size == 0) return null;
      return _GiftStoryVideoResult(
        blob: blob,
        mime: mime,
        extension: mime.startsWith('video/mp4') ? 'mp4' : 'webm',
      );
    } catch (error) {
      debugPrint(
          'Stored Gift Story video unavailable; rendering again: $error');
      return null;
    }
  }

  Future<void> _persistRenderedStoryVideo(_GiftStoryVideoResult result) async {
    final giftId = '${widget.gift['id'] ?? ''}'.trim();
    if (giftId.isEmpty) return;
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final upload =
        await functions.httpsCallable('createGiftStoryVideoUpload').call({
      'giftRequestId': giftId,
      'token': _storyAccessToken,
      'extension': result.extension,
    });
    final payload = Map<String, dynamic>.from(upload.data as Map);
    await html.HttpRequest.request(
      '${payload['uploadUrl']}',
      method: 'PUT',
      requestHeaders: {'Content-Type': result.mime},
      sendData: result.blob,
    );
    await functions.httpsCallable('finalizeGiftStoryVideoUpload').call({
      'giftRequestId': giftId,
      'token': _storyAccessToken,
      'storagePath': payload['storagePath'],
      'mime': result.mime,
    });
  }

  Future<_GiftStoryVideoResult> _renderStoryVideo() async {
    const width = 720;
    const height = 1280;
    const framesPerSecond = 24;
    const framesPerChapter = 48;
    final canvas = html.CanvasElement(width: width, height: height);
    final context = canvas.context2D;
    final stream = canvas.captureStream(framesPerSecond);
    html.AudioElement? exportAudio;
    final audioUrl = _currentAudioUrl();
    if (_musicEnabled && audioUrl.isNotEmpty) {
      try {
        exportAudio = html.AudioElement(audioUrl)
          ..crossOrigin = 'anonymous'
          ..loop = true
          ..preload = 'auto';
        final audioStream = exportAudio.captureStream();
        for (final track in audioStream.getAudioTracks()) {
          stream.addTrack(track);
        }
        await exportAudio.play();
      } catch (error) {
        debugPrint(
            'Gift Story export audio unavailable; rendering silent: $error');
        exportAudio?.pause();
        exportAudio = null;
      }
    }
    final mime = _preferredStoryVideoMime();
    final recorder = html.MediaRecorder(stream, {
      'mimeType': mime,
      'videoBitsPerSecond': 5000000,
    });
    final chunks = <html.Blob>[];
    final stopped = Completer<void>();
    recorder.on['dataavailable'].listen((event) {
      final data = (event as html.BlobEvent).data;
      if (data != null && data.size > 0) chunks.add(data);
    });
    recorder.on['stop'].listen((_) {
      if (!stopped.isCompleted) stopped.complete();
    });
    recorder.onError.listen((event) {
      if (!stopped.isCompleted) {
        stopped.completeError(StateError('Browser video recorder failed.'));
      }
    });
    recorder.start(500);
    final photos = await _loadStoryExportPhotos();
    final chapters = _chapters;
    for (var chapterIndex = 0; chapterIndex < chapters.length; chapterIndex++) {
      for (var frame = 0; frame < framesPerChapter; frame++) {
        final phase = frame / (framesPerChapter - 1);
        _paintStoryVideoFrame(
          context,
          chapters[chapterIndex],
          chapterIndex,
          chapters.length,
          phase,
          photos[chapters[chapterIndex].photoUrl],
        );
        if (mounted && frame % 8 == 0) {
          setState(() {
            _exportProgress = (chapterIndex * framesPerChapter + frame + 1) /
                (chapters.length * framesPerChapter);
          });
        }
        await Future<void>.delayed(
          const Duration(milliseconds: 42),
        );
      }
    }
    recorder.stop();
    await stopped.future.timeout(const Duration(seconds: 8));
    exportAudio?.pause();
    for (final track in stream.getTracks()) {
      track.stop();
    }
    if (chunks.isEmpty) {
      throw StateError('The browser did not produce a video file.');
    }
    final blob = html.Blob(chunks, mime);
    return _GiftStoryVideoResult(
      blob: blob,
      mime: mime,
      extension: mime.startsWith('video/mp4') ? 'mp4' : 'webm',
    );
  }

  String _preferredStoryVideoMime() {
    const options = [
      'video/mp4;codecs=avc1.42E01E',
      'video/mp4',
      'video/webm;codecs=vp9,opus',
      'video/webm;codecs=vp8,opus',
      'video/webm',
    ];
    for (final option in options) {
      if (html.MediaRecorder.isTypeSupported(option)) return option;
    }
    throw UnsupportedError('This browser cannot render MP4 or WebM video.');
  }

  Future<Map<String?, html.ImageElement>> _loadStoryExportPhotos() async {
    final result = <String?, html.ImageElement>{};
    for (final url in _chapters.map((chapter) => chapter.photoUrl).toSet()) {
      if (url == null || url.isEmpty) continue;
      try {
        final image = html.ImageElement()
          ..crossOrigin = 'anonymous'
          ..src = url;
        await image.onLoad.first.timeout(const Duration(seconds: 10));
        result[url] = image;
      } catch (error) {
        debugPrint('Gift Story export photo skipped: $url ($error)');
      }
    }
    return result;
  }

  void _paintStoryVideoFrame(
    html.CanvasRenderingContext2D context,
    _GiftStoryChapter chapter,
    int index,
    int total,
    double phase,
    html.ImageElement? photo,
  ) {
    const width = 720.0;
    const height = 1280.0;
    context
      ..save()
      ..fillStyle = '#050816'
      ..fillRect(0, 0, width, height);
    if (photo != null && photo.naturalWidth > 0 && photo.naturalHeight > 0) {
      final imageRatio = photo.naturalWidth / photo.naturalHeight;
      const frameRatio = width / height;
      final scale = 1 + phase * 0.035;
      if (imageRatio > frameRatio) {
        final sourceWidth = photo.naturalHeight * frameRatio / scale;
        final sourceX = (photo.naturalWidth - sourceWidth) / 2;
        context.drawImageScaledFromSource(
          photo,
          sourceX,
          0,
          sourceWidth,
          photo.naturalHeight,
          0,
          0,
          width,
          height,
        );
      } else {
        final sourceHeight = photo.naturalWidth / frameRatio / scale;
        final sourceY = (photo.naturalHeight - sourceHeight) / 2;
        context.drawImageScaledFromSource(
          photo,
          0,
          sourceY,
          photo.naturalWidth,
          sourceHeight,
          0,
          0,
          width,
          height,
        );
      }
    } else {
      final gradient = context.createLinearGradient(0, 0, width, height)
        ..addColorStop(0, '#121938')
        ..addColorStop(0.48, '#6D5EF8')
        ..addColorStop(1, '#050816');
      context
        ..fillStyle = gradient
        ..fillRect(0, 0, width, height);
    }
    final overlay = context.createLinearGradient(0, 0, 0, height)
      ..addColorStop(0, 'rgba(5,8,22,.36)')
      ..addColorStop(.45, 'rgba(5,8,22,.08)')
      ..addColorStop(1, 'rgba(5,8,22,.92)');
    context
      ..fillStyle = overlay
      ..fillRect(0, 0, width, height);
    for (var i = 0; i < total; i++) {
      context
        ..fillStyle = i <= index ? '#ffffff' : 'rgba(255,255,255,.22)'
        ..fillRect(
            28 + i * ((width - 56) / total), 30, ((width - 56) / total) - 5, 5);
    }
    context
      ..fillStyle = '#ffffff'
      ..font = '700 17px Helvetica, Arial, sans-serif'
      ..fillText('giftsbycircum', 30, 76)
      ..fillStyle = 'rgba(255,255,255,.68)'
      ..font = '600 13px Helvetica, Arial, sans-serif'
      ..fillText('NOW  ·  ${index + 1}/$total', 30, 99);
    final entrance = Curves.easeOut.transform(math.min(1, phase * 4));
    context
      ..globalAlpha = entrance
      ..fillStyle = 'rgba(8,11,31,.68)'
      ..fillRect(28, 840 + (1 - entrance) * 28, width - 56, 330)
      ..fillStyle = '#ffffff'
      ..font = '800 54px Helvetica, Arial, sans-serif';
    var y = 920 + (1 - entrance) * 28;
    y = _paintWrappedText(context, chapter.title, 52, y, width - 104, 60, 3);
    context
      ..fillStyle = 'rgba(255,255,255,.88)'
      ..font = '650 25px Helvetica, Arial, sans-serif';
    _paintWrappedText(context, chapter.body.replaceAll('\n', ' '), 52, y + 22,
        width - 104, 34, 4);
    context
      ..globalAlpha = 1
      ..fillStyle = 'rgba(255,255,255,.72)'
      ..font = '700 16px Helvetica, Arial, sans-serif'
      ..fillText('CREATED WITH GIFTS BY CIRCUM', 30, 1232)
      ..restore();
  }

  double _paintWrappedText(
    html.CanvasRenderingContext2D context,
    String text,
    double x,
    double y,
    double maxWidth,
    double lineHeight,
    int maxLines,
  ) {
    final words = text.split(RegExp(r'\s+'));
    var line = '';
    var lines = 0;
    for (final word in words) {
      final candidate = line.isEmpty ? word : '$line $word';
      if ((context.measureText(candidate).width ?? 0) > maxWidth &&
          line.isNotEmpty) {
        context.fillText(line, x, y);
        y += lineHeight;
        lines++;
        if (lines >= maxLines) return y;
        line = word;
      } else {
        line = candidate;
      }
    }
    if (line.isNotEmpty && lines < maxLines) {
      context.fillText(line, x, y);
      y += lineHeight;
    }
    return y;
  }

  String _currentAudioUrl() {
    return '${widget.gift['giftStoryCustomAudioUrl'] ?? ''}'.trim();
  }

  Future<void> _ensureAudio() async {
    final url = _currentAudioUrl();
    if (url.isEmpty) return;
    final existing = _audio;
    if (existing != null && existing.src == url) {
      existing.muted = _muted;
      existing.loop = true;
      return;
    }
    existing?.pause();
    final audio = html.AudioElement(url)
      ..loop = true
      ..muted = _muted
      ..preload = 'auto';
    audio.onError.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _musicEnabled = false;
        _audio = null;
        _musicPrompt =
            'Audio could not play. The story will continue silently.';
      });
      debugPrint(
          'Gift Story audio playback error: network=${audio.networkState}, ready=${audio.readyState}, src=${audio.src}');
    });
    _audio = audio;
  }

  Future<void> _togglePlayback() async {
    if (!_musicEnabled || _currentAudioUrl().isEmpty) return;
    if (_playing) {
      _audio?.pause();
      setState(() {
        _playing = false;
        _musicPrompt = null;
      });
      return;
    }
    try {
      await _ensureAudio();
      await _audio?.play();
      if (!mounted) return;
      setState(() {
        _playing = true;
        _musicPrompt = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _musicEnabled = false;
        _audio = null;
        _musicPrompt =
            'Audio could not play. The story will continue silently.';
      });
      debugPrint('Gift Story audio play failed: $error');
    }
  }

  void _toggleMute() {
    final nextMuted = !_muted;
    _audio?.muted = nextMuted;
    setState(() {
      _muted = nextMuted;
    });
  }

  Widget _musicControls(_CircumColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _playing ? 'Pause music' : 'Play music',
            onPressed: _togglePlayback,
            icon: Icon(
              _playing ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
          ),
          IconButton(
            tooltip: _muted ? 'Unmute music' : 'Mute music',
            onPressed: _toggleMute,
            icon: Icon(
              _muted || !_musicEnabled ? Icons.volume_off : Icons.volume_up,
              color: Colors.white,
            ),
          ),
          const Text('Audio',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _storySlide(BuildContext context, _GiftStoryChapter chapter) {
    final colors = widget.colors;
    final hasPhoto = chapter.photoUrl != null && chapter.photoUrl!.isNotEmpty;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: Offset(_transitionDirection.toDouble(), 0),
          end: Offset.zero,
        ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: ClipRRect(
        key: ValueKey('$_chapter-${chapter.photoUrl ?? chapter.title}'),
        borderRadius: BorderRadius.circular(34),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPhoto)
              Image.network(
                chapter.photoUrl!,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) =>
                    _storyPlaceholderBackground(colors),
              )
            else
              _storyPlaceholderBackground(colors),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.22),
                      Colors.transparent,
                      Colors.black.withValues(alpha: hasPhoto ? 0.76 : 0.50),
                    ],
                    stops: const [0, 0.42, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topLeft,
                    radius: 1.35,
                    colors: [
                      colors.adminAccent.withValues(alpha: 0.20),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _storySlideBadge(chapter, hasPhoto),
                  const Spacer(),
                  _storyCaptionPanel(chapter),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _storyPlaceholderBackground(_CircumColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.adminAccent.withValues(alpha: 0.46),
            colors.adminGlow.withValues(alpha: 0.30),
            const Color(0xff050914),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.adminGlow.withValues(alpha: 0.25),
                boxShadow: [
                  BoxShadow(
                    color: colors.adminGlow.withValues(alpha: 0.34),
                    blurRadius: 80,
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: Icon(
              Icons.card_giftcard,
              color: Colors.white.withValues(alpha: 0.18),
              size: 156,
            ),
          ),
        ],
      ),
    );
  }

  Widget _storySlideBadge(_GiftStoryChapter chapter, bool hasPhoto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: hasPhoto ? 0.28 : 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: widget.colors.adminGlow.withValues(alpha: 0.22),
            blurRadius: 26,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chapter.icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            hasPhoto ? 'Gift memory' : 'Gift Story',
            style: GoogleFonts.dmSans(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _storyCaptionPanel(_GiftStoryChapter chapter) {
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: height * 0.70),
      padding: EdgeInsets.all(width < 420 ? 20 : 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width < 420 ? 26 : 32),
        color: Color.alphaBlend(
          Colors.white.withValues(alpha: 0.16),
          Colors.black.withValues(alpha: 0.34),
        ),
        backgroundBlendMode: BlendMode.overlay,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xffa8edea).withValues(alpha: 0.20),
            const Color(0xffc9b8ff).withValues(alpha: 0.20),
            const Color(0xffffd6e8).withValues(alpha: 0.20),
            const Color(0xffb8f0d8).withValues(alpha: 0.20),
            const Color(0xffd4c5ff).withValues(alpha: 0.20),
          ],
          stops: const [0, 0.25, 0.5, 0.75, 1],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xffc9b8ff).withValues(alpha: 0.34),
            blurRadius: 48,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              chapter.title,
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontSize: 38,
                height: 1.02,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              chapter.body,
              style: GoogleFonts.dmSans(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 18,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (chapter.chips.isNotEmpty) ...[
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: chapter.chips
                    .map((chip) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: Colors.white.withValues(alpha: 0.14),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.16)),
                          ),
                          child: Text(
                            chip,
                            style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
            if (chapter.audioUrl != null && chapter.audioUrl!.isNotEmpty) ...[
              const SizedBox(height: 22),
              _CircumVoiceAudioPlayer(
                url: chapter.audioUrl!,
                durationSeconds: chapter.audioDurationSeconds,
              ),
            ],
            if (chapter.finalChapter) ...[
              const SizedBox(height: 24),
              _storyFinalActions(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _storyFinalActions() {
    final sharingEnabled = widget.gift['giftStoryShareEnabled'] != false &&
        _sharePrivacy != 'private';
    const platforms = [
      ('WhatsApp', Icons.chat),
      ('Instagram Story', Icons.camera_alt_outlined),
      ('Instagram DM', Icons.send_outlined),
      ('Facebook', Icons.facebook),
      ('Facebook Story', Icons.auto_stories_outlined),
      ('TikTok', Icons.music_note),
      ('X', Icons.alternate_email),
      ('Snapchat', Icons.photo_camera_front_outlined),
      ('Messages', Icons.sms_outlined),
      ('Email', Icons.email_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Share This Moment',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Created with Gifts by Circum',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Public Share'),
              selected: _sharePrivacy == 'public',
              onSelected: (_) => _updateSharePrivacy('public'),
            ),
            ChoiceChip(
              label: const Text('Unlisted Share Link'),
              selected: _sharePrivacy == 'unlisted',
              onSelected: (_) => _updateSharePrivacy('unlisted'),
            ),
            ChoiceChip(
              label: const Text('Private'),
              selected: _sharePrivacy == 'private',
              onSelected: (_) => _updateSharePrivacy('private'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _storyShareButton(
              _exportingVideo ? 'Rendering video' : 'Share',
              Icons.ios_share,
              sharingEnabled && !_exportingVideo
                  ? () => _exportStoryVideo(shareAfter: true)
                  : null,
            ),
            for (final platform in platforms)
              _storyShareButton(
                platform.$1,
                platform.$2,
                sharingEnabled ? () => _launchStoryShare(platform.$1) : null,
              ),
            _storyShareButton('Copy Link', Icons.link, _copyStoryLink),
            _storyShareButton(
              'Save Current Slide',
              Icons.image_outlined,
              _downloadCurrentSlide,
            ),
            _storyShareButton(
              _exportingVideo
                  ? 'Rendering ${(_exportProgress * 100).round()}%'
                  : 'Download Video',
              Icons.download,
              _exportingVideo ? null : _exportStoryVideo,
            ),
            _storyShareButton(
              'Save to Device',
              Icons.save_alt,
              _exportingVideo ? null : _exportStoryVideo,
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse('https://circumuk.com/?app=gifts'),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('Learn More · Send a Gift · Join Waitlist'),
        ),
      ],
    );
  }

  Widget _storyShareButton(String label, IconData icon, VoidCallback? onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.38),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final chapter = _chapters[_chapter];
    return Scaffold(
      backgroundColor: const Color(0xff050914),
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _next();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _previous();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTapUp: (details) {
            final width = MediaQuery.sizeOf(context).width;
            details.localPosition.dx < width * 0.35 ? _previous() : _next();
          },
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -120) _next();
            if (velocity > 120) _previous();
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topLeft,
                      radius: 1.25,
                      colors: [
                        colors.adminAccent.withValues(alpha: 0.42),
                        colors.adminGlow.withValues(alpha: 0.22),
                        const Color(0xff050914),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: List.generate(
                                _chapters.length,
                                (index) => Expanded(
                                  child: Container(
                                    height: 4,
                                    margin: const EdgeInsets.only(right: 5),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      color:
                                          Colors.white.withValues(alpha: 0.22),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: index < _chapter
                                          ? 1
                                          : index == _chapter
                                              ? _chapterProgress
                                              : 0,
                                      child:
                                          const ColoredBox(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close Gift Story',
                            onPressed: widget.onClose,
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_musicEnabled)
                        Align(
                          alignment: Alignment.centerRight,
                          child: _musicControls(colors),
                        ),
                      if (_musicPrompt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _musicPrompt!,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.76),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final storyWidth = math.min(
                              480.0,
                              constraints.maxHeight * 9 / 16,
                            );
                            return Center(
                              child: SizedBox(
                                width: storyWidth,
                                height: storyWidth * 16 / 9,
                                child: _storySlide(context, chapter),
                              ),
                            );
                          },
                        ),
                      ),
                      Semantics(
                        label:
                            'Gift Story chapter ${_chapter + 1} of ${_chapters.length}. Tap right for next or left for previous.',
                        child: Text(
                          'Tap or swipe to move through your Gift Story.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              color: Colors.white.withValues(alpha: 0.70),
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
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

class _GiftStoryVideoResult {
  final html.Blob blob;
  final String mime;
  final String extension;

  const _GiftStoryVideoResult({
    required this.blob,
    required this.mime,
    required this.extension,
  });
}

class _GiftStoryChapter {
  final IconData icon;
  final String title;
  final String body;
  final List<String> chips;
  final bool finalChapter;
  final String? photoUrl;
  final String? audioUrl;
  final int? audioDurationSeconds;

  const _GiftStoryChapter({
    required this.icon,
    required this.title,
    required this.body,
    this.chips = const [],
    this.finalChapter = false,
    this.photoUrl,
    this.audioUrl,
    this.audioDurationSeconds,
  });
}

int? _giftStoryIntFromDynamic(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

class _CircumVoiceAudioPlayer extends StatefulWidget {
  final String url;
  final int? durationSeconds;

  const _CircumVoiceAudioPlayer({
    required this.url,
    this.durationSeconds,
  });

  @override
  State<_CircumVoiceAudioPlayer> createState() =>
      _CircumVoiceAudioPlayerState();
}

class _CircumVoiceAudioPlayerState extends State<_CircumVoiceAudioPlayer> {
  html.AudioElement? _audio;
  StreamSubscription? _timeSub;
  StreamSubscription? _endedSub;
  bool _playing = false;
  double _position = 0;
  double _duration = 0;

  @override
  void initState() {
    super.initState();
    _duration = (widget.durationSeconds ?? 0).toDouble();
    _audio = html.AudioElement(widget.url)..preload = 'metadata';
    _audio!.onLoadedMetadata.listen((_) {
      if (!mounted) return;
      final duration = _audio!.duration;
      if (duration.isFinite && duration > 0) {
        setState(() => _duration = duration.toDouble());
      }
    });
    _timeSub = _audio!.onTimeUpdate.listen((_) {
      if (!mounted) return;
      setState(() => _position = _audio!.currentTime.toDouble());
    });
    _endedSub = _audio!.onEnded.listen((_) {
      if (!mounted) return;
      setState(() {
        _playing = false;
        _position = 0;
      });
    });
  }

  @override
  void dispose() {
    _timeSub?.cancel();
    _endedSub?.cancel();
    _audio?.pause();
    _audio = null;
    super.dispose();
  }

  Future<void> _play() async {
    final audio = _audio;
    if (audio == null) return;
    await audio.play();
    if (mounted) setState(() => _playing = true);
  }

  void _pause() {
    _audio?.pause();
    if (mounted) setState(() => _playing = false);
  }

  void _stop() {
    final audio = _audio;
    if (audio == null) return;
    audio
      ..pause()
      ..currentTime = 0;
    if (mounted) {
      setState(() {
        _playing = false;
        _position = 0;
      });
    }
  }

  String _format(double seconds) {
    final safe = seconds.isFinite ? seconds.round().clamp(0, 3599) : 0;
    final minutes = safe ~/ 60;
    final remainder = safe % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final max =
        (_duration > 0 ? _duration : math.max(_position, 1.0)).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Slider(
          value: _position.clamp(0, max).toDouble(),
          max: max,
          onChanged: (value) {
            final audio = _audio;
            if (audio == null) return;
            audio.currentTime = value;
            setState(() => _position = value);
          },
        ),
        Text(
          '${_format(_position)} / ${_format(max)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _playing ? null : _play,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Play'),
          ),
          OutlinedButton.icon(
            onPressed: _playing ? _pause : null,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
          ),
          OutlinedButton.icon(
            onPressed: _position > 0 || _playing ? _stop : null,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(widget.url)),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download'),
          ),
        ]),
      ],
    );
  }
}

class _CircumColors {
  final bool dark;

  const _CircumColors(this.dark);

  Color get background => dark ? Colors.black : Colors.white;
  Color get appBackground => dark ? const Color(0xff030712) : Colors.white;
  Color get stage => dark ? const Color(0xff111827) : const Color(0xfff3f4f6);
  Color get band => dark ? const Color(0xff0f172a) : const Color(0xfff8fafc);
  Color get panel => dark ? const Color(0xff111827) : Colors.white;
  Color get field => dark ? const Color(0xff1f2937) : const Color(0xfff3f4f6);
  Color get border => dark ? const Color(0xff1f2937) : const Color(0xffe5e7eb);
  Color get text => dark ? Colors.white : Colors.black;
  Color get inverseText => dark ? Colors.black : Colors.white;
  Color get mutedText =>
      dark ? const Color(0xff9ca3af) : const Color(0xff6b7280);
  Color get success => const Color(0xff16a34a);
  Color get warning => const Color(0xfff59e0b);
  Color get adminChrome =>
      dark ? const Color(0xff07111f) : const Color(0xfff8fbff);
  Color get adminAccent =>
      dark ? const Color(0xff38bdf8) : const Color(0xff2563eb);
  Color get adminGlow =>
      dark ? const Color(0xffa855f7) : const Color(0xff38bdf8);
}
