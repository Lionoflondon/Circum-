import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;

import 'app/security/circum_app_check.dart';
import 'env/env.dart';

const _privateBuild = bool.fromEnvironment('CIRCUM_PRIVATE_GIFTS_TEST');
const _origin =
    'https://giftqa---circum-qa-special-flow-j2b7cicfwq-uc.a.run.app';

void validateGiftsTestBuild({required bool enabled, required String mode}) {
  if (!enabled || mode != 'test') {
    throw StateError(
        'This entry point requires an explicit private TEST build.');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    validateGiftsTestBuild(
        enabled: _privateBuild, mode: Env.paymentEnvironment);
    Env.validatedPaymentEnvironment(
        environment: Env.paymentEnvironment,
        publishableKey: Env.stripePublishableKey);
    await Firebase.initializeApp();
    await initializeCircumAppCheck();
    runApp(const GiftsTestApp());
  } catch (_) {
    runApp(const MaterialApp(
      home:
          Scaffold(body: Center(child: Text('Private TEST startup blocked.'))),
    ));
  }
}

class GiftsTestApp extends StatelessWidget {
  const GiftsTestApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Circum Gifts TEST',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const _Journey(),
      );
}

class _Journey extends StatefulWidget {
  const _Journey();

  @override
  State<_Journey> createState() => _JourneyState();
}

class _JourneyState extends State<_Journey> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fixture = TextEditingController();
  String? _role;
  String _result = 'Sign in using an approved QA account.';
  bool _busy = false;

  Future<Map<String, dynamic>> _call(String action,
      [Map<String, dynamic> extra = const {}]) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final check = await FirebaseAppCheck.instance.getToken();
    if (token == null || check == null || check.isEmpty) {
      throw StateError('Authentication and App Check are required.');
    }
    final response = await http
        .post(Uri.parse('$_origin/qaGiftJourney'),
            headers: {
              'Authorization': 'Bearer $token',
              'X-Firebase-AppCheck': check,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'data': {
                'action': action,
                if (_fixture.text.isNotEmpty) 'fixtureId': _fixture.text.trim(),
                ...extra,
              }
            }))
        .timeout(const Duration(seconds: 40));
    final body = jsonDecode(response.body) as Map;
    if (response.statusCode != 200 || body['error'] != null) {
      final error = body['error'];
      throw StateError(error is Map
          ? '${error['message'] ?? 'Private TEST request rejected.'}'
          : 'Private TEST request rejected.');
    }
    return Map<String, dynamic>.from(body['result'] as Map);
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      if (mounted) setState(() => _result = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    // No credential is bundled, logged or retained in a text field.
    final email = _email.text.trim();
    final password = _password.text;
    _password.clear();
    await FirebaseAuth.instance.signOut();
    if (mounted) setState(() => _role = null);
    await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);
    try {
      final identity = await _call('identity');
      if (identity['testOnly'] != true ||
          !['sender', 'admin', 'rider'].contains(identity['role'])) {
        throw StateError('Approved QA role required.');
      }
      if (mounted) {
        setState(() {
          _role = identity['role'] as String;
          _result = 'Approved $_role session. TEST only.';
        });
      }
    } catch (_) {
      await FirebaseAuth.instance.signOut();
      rethrow;
    }
  }

  Future<void> _action(String action,
      [Map<String, dynamic> extra = const {}]) async {
    final result = await _call(action, extra);
    if (!mounted) return;
    if (action == 'prepare') _fixture.text = result['fixtureId'] as String;
    if (action == 'cleanup') _fixture.clear();
    setState(
        () => _result = const JsonEncoder.withIndent('  ').convert(result));
  }

  Future<void> _pay() async {
    final key = Env.stripePublishableKey.trim();
    Env.validatedPaymentEnvironment(environment: 'test', publishableKey: key);
    final checkout = await _call('checkout_native');
    if (checkout['paymentStatus'] == 'paid') {
      await _action('finalize_native_payment');
      return;
    }
    if (checkout['stripeMode'] != 'TEST' || checkout['amountPence'] != 5000) {
      throw StateError('Fixed £50 TEST checkout required.');
    }
    Stripe.publishableKey = key;
    Stripe.urlScheme = 'circum';
    await Stripe.instance.applySettings();
    // One-off card only: no saved cards, wallet payments or customer key.
    await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
      paymentIntentClientSecret: checkout['clientSecret'] as String,
      merchantDisplayName: 'Circum Gifts TEST',
      returnURL: 'circum://stripe-redirect',
      allowsDelayedPaymentMethods: false,
    ));
    await Stripe.instance.presentPaymentSheet();
    // This verifies the provider outcome; it cannot manufacture a payment.
    await _action('finalize_native_payment');
  }

  Widget _button(String label, Future<void> Function() action) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FilledButton(
          onPressed: _busy ? null : () => _run(action),
          child: Text(label),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Circum Gifts · PRIVATE TEST')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
            'Isolated £50 TEST card payment. Customer email, push, dispatch '
            'and payouts are suppressed. Completion here is a TEST event; '
            'physical delivery and the released Rider/PIN path are separate.',
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'QA email')),
          TextField(
              controller: _password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'QA password')),
          _button('Sign in as QA operator', _login),
          if (_role != null) ...[
            Text('Authenticated role: $_role'),
            TextField(
                controller: _fixture,
                decoration:
                    const InputDecoration(labelText: 'Private fixture ID')),
            if (_role == 'admin') ...[
              _button(
                  'Prepare private Gift',
                  () => _action('prepare', {
                        'requestId':
                            'native_${DateTime.now().millisecondsSinceEpoch}',
                      })),
              for (final status in [
                'approved',
                'curation_started',
                'ready_for_gift_delivery'
              ])
                _button(status.replaceAll('_', ' '),
                    () => _action('advance', {'status': status})),
              _button(
                  'Clean fixture and TEST customer', () => _action('cleanup')),
            ],
            if (_role == 'sender') ...[
              _button('Open £50 TEST payment sheet', _pay),
              _button('Verify completed TEST payment',
                  () => _action('finalize_native_payment')),
              _button('Read Gift Story', () => _action('story')),
            ],
            if (_role == 'rider')
              _button('Record private completion event',
                  () => _action('complete_delivery')),
            _button(
                'Read email and notification evidence', () => _action('read')),
            _button('Sign out', () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) setState(() => _role = null);
            }),
          ],
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 20),
          SelectableText(_result),
        ]),
      );

  @override
  void dispose() {
    for (final controller in [_email, _password, _fixture]) {
      controller.dispose();
    }
    super.dispose();
  }
}
