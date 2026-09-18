import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

const _categories = <String, String>{
  'circum_updates': 'CIRCUM Updates',
  'offers_rewards': 'Offers & Rewards',
  'rider_opportunities': 'Rider Opportunities',
  'business_partnerships': 'Business & Partnerships',
};

class NewsletterSignupSection extends StatefulWidget {
  const NewsletterSignupSection({
    super.key,
    required this.background,
    required this.panel,
    required this.text,
    required this.mutedText,
    required this.border,
    required this.onPrivacy,
  });

  final Color background;
  final Color panel;
  final Color text;
  final Color mutedText;
  final Color border;
  final Uri onPrivacy;

  @override
  State<NewsletterSignupSection> createState() =>
      _NewsletterSignupSectionState();
}

class _NewsletterSignupSectionState extends State<NewsletterSignupSection> {
  final _email = TextEditingController();
  final _selected = <String>{'circum_updates'};
  bool _showPreferences = false;
  bool _submitting = false;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_event('newsletter_signup_viewed'));
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _event(String event) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('recordNewsletterAnalytics')
          .call({'event': event, 'source': 'homepage'});
    } catch (_) {
      // Privacy-conscious analytics must never affect signup.
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      unawaited(_event('newsletter_signup_failed'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    unawaited(_event('newsletter_signup_started'));
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('submitNewsletterSignup')
          .call({
        'email': email,
        'categories': _selected.toList(growable: false),
        'source': 'homepage',
        'website': '',
      });
      if (!mounted) return;
      setState(() => _success = true);
      unawaited(_event('newsletter_signup_completed'));
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() =>
          _error = error.message ?? 'Could not join right now. Try again.');
      unawaited(_event('newsletter_signup_failed'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not join right now. Try again.');
      unawaited(_event('newsletter_signup_failed'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 680;
    return Container(
      width: double.infinity,
      color: widget.background,
      padding:
          EdgeInsets.symmetric(horizontal: compact ? 20 : 28, vertical: 56),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.panel,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: widget.border),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 34,
                    offset: const Offset(0, 16))
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(compact ? 22 : 38),
              child: _success ? _successState() : _form(compact),
            ),
          ),
        ),
      ),
    );
  }

  Widget _successState() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded,
              color: const Color(0xff38bdf8), size: 34),
          const SizedBox(height: 14),
          Text('You’re in. Welcome to CIRCUM.',
              style: TextStyle(
                  color: widget.text,
                  fontSize: 27,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
              'Get product launches, CIRCUM updates, offers and early-access opportunities. Unsubscribe anytime.',
              style: TextStyle(color: widget.mutedText, height: 1.45)),
        ],
      );

  Widget _form(bool compact) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stay in the CIRCUM',
              style: TextStyle(
                  color: widget.text,
                  fontSize: compact ? 31 : 40,
                  fontWeight: FontWeight.w900,
                  height: 1.05)),
          const SizedBox(height: 12),
          Text('Delivery is changing. Be the first to know what’s next.',
              style: TextStyle(
                  color: widget.mutedText, fontSize: 17, height: 1.4)),
          const SizedBox(height: 24),
          if (compact) ...[
            _emailField(),
            const SizedBox(height: 12),
            _submitButton(),
          ] else
            Row(children: [
              Expanded(child: _emailField()),
              const SizedBox(width: 12),
              _submitButton()
            ]),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    color: Color(0xffff9aa2), fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () =>
                setState(() => _showPreferences = !_showPreferences),
            icon:
                Icon(_showPreferences ? Icons.expand_less : Icons.tune_rounded),
            label: Text(_showPreferences
                ? 'Hide preferences'
                : 'Choose what you hear about'),
          ),
          if (_showPreferences) ...[
            const SizedBox(height: 4),
            Text(
                'CIRCUM Updates is included. Select any additional interests you want.',
                style: TextStyle(color: widget.mutedText, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.entries
                  .map((entry) => FilterChip(
                        label: Text(entry.value),
                        selected: _selected.contains(entry.key),
                        onSelected: entry.key == 'circum_updates'
                            ? null
                            : (selected) => setState(() {
                                  if (selected) {
                                    _selected.add(entry.key);
                                  } else {
                                    _selected.remove(entry.key);
                                  }
                                }),
                      ))
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 4, children: [
            Text('By joining, you agree to receive CIRCUM marketing emails. ',
                style: TextStyle(color: widget.mutedText, fontSize: 12)),
            Link(
                uri: widget.onPrivacy,
                target: LinkTarget.self,
                builder: (_, followLink) => TextButton(
                    onPressed: followLink,
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 20)),
                    child: const Text('Privacy Policy'))),
            Text(' Unsubscribe anytime.',
                style: TextStyle(color: widget.mutedText, fontSize: 12)),
          ]),
        ],
      );

  Widget _emailField() => TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        onChanged: (_) => _error == null ? null : setState(() => _error = null),
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
            labelText: 'Email address', border: OutlineInputBorder()),
      );

  Widget _submitButton() => FilledButton(
        onPressed: _submitting ? null : _submit,
        style: FilledButton.styleFrom(minimumSize: const Size(164, 56)),
        child: _submitting
            ? const SizedBox.square(
                dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Join CIRCUM →'),
      );
}

class NewsletterPreferencesPage extends StatefulWidget {
  const NewsletterPreferencesPage(
      {super.key,
      required this.background,
      required this.text,
      required this.mutedText});
  final Color background;
  final Color text;
  final Color mutedText;
  @override
  State<NewsletterPreferencesPage> createState() =>
      _NewsletterPreferencesPageState();
}

class _NewsletterPreferencesPageState extends State<NewsletterPreferencesPage> {
  final _selected = <String>{};
  bool _loading = true;
  bool _saving = false;
  String? _message;
  late final String _token = Uri.base.queryParameters['token'] ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getNewsletterPreferences')
          .call({'token': _token, 'website': ''});
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['status'] == 'unsubscribed') {
        _message = 'You’ve already been unsubscribed.';
      }
      _selected.addAll(
          (data['categories'] as List? ?? const []).map((value) => '$value'));
    } on FirebaseFunctionsException catch (error) {
      _message = error.message ?? 'This link is invalid or has expired.';
    } catch (_) {
      _message = 'This link is invalid or has expired.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save({required bool unsubscribe}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(unsubscribe
              ? 'unsubscribeNewsletter'
              : 'updateNewsletterPreferences')
          .call({
        'token': _token,
        if (!unsubscribe) 'categories': _selected.toList(growable: false),
        'website': '',
      });
      if (mounted) {
        setState(() => _message = unsubscribe
            ? 'You’ve been unsubscribed. You won’t receive further CIRCUM marketing emails.'
            : 'Your communication preferences have been updated.');
      }
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(() =>
            _message = error.message ?? 'Could not update your preferences.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Leave the CIRCUM?',
                  style: TextStyle(
                      color: widget.text,
                      fontSize: 34,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Text(
                  'You can update what you receive, or unsubscribe from all CIRCUM marketing emails.',
                  style: TextStyle(color: widget.mutedText)),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!,
                    style: TextStyle(
                        color: widget.text, fontWeight: FontWeight.w700)),
              ] else ...[
                const SizedBox(height: 18),
                ..._categories.entries.map((entry) {
                  return CheckboxListTile(
                    value: _selected.contains(entry.key),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selected.add(entry.key);
                      } else {
                        _selected.remove(entry.key);
                      }
                    }),
                    title:
                        Text(entry.value, style: TextStyle(color: widget.text)),
                  );
                }),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  OutlinedButton(
                      onPressed:
                          _saving ? null : () => _save(unsubscribe: false),
                      child: const Text('Save preferences')),
                  FilledButton(
                      onPressed:
                          _saving ? null : () => _save(unsubscribe: true),
                      child: const Text('Unsubscribe from all'))
                ]),
              ],
            ],
          );
    return Scaffold(
        backgroundColor: widget.background,
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Padding(
                        padding: const EdgeInsets.all(24), child: content)))));
  }
}
