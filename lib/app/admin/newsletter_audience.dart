import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class _NewsletterAdminRequestException implements Exception {
  const _NewsletterAdminRequestException(this.message);
  final String message;
}

Future<Map<String, dynamic>> _callNewsletterAdmin(String name,
    [Map<String, dynamic> data = const {}]) async {
  final appCheck = await FirebaseAppCheck.instance.getToken();
  final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (appCheck == null ||
      appCheck.isEmpty ||
      idToken == null ||
      idToken.isEmpty) {
    throw const _NewsletterAdminRequestException(
        'Sign in again and complete Circum security verification.');
  }
  final response = await http.post(
    Uri.base.resolve('/newsletter-api/v1/callable/$name'),
    headers: {
      'content-type': 'application/json',
      'x-firebase-appcheck': appCheck,
      'authorization': 'Bearer $idToken',
    },
    body: jsonEncode({'data': data}),
  );
  final payload = jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode != 200) {
    final error = payload['error'] as Map?;
    throw _NewsletterAdminRequestException(
        '${error?['message'] ?? 'Newsletter request failed.'}');
  }
  return Map<String, dynamic>.from(payload['result'] as Map);
}

String newsletterCsvCell(Object? value) {
  var text = '${value ?? ''}';
  if (RegExp(r'^[\s]*[=+@\-\t\r\n]').hasMatch(text)) text = "'$text";
  return '"${text.replaceAll('"', '""')}"';
}

class NewsletterAudienceModule extends StatefulWidget {
  const NewsletterAudienceModule({super.key});

  @override
  State<NewsletterAudienceModule> createState() =>
      _NewsletterAudienceModuleState();
}

class _NewsletterAudienceModuleState extends State<NewsletterAudienceModule> {
  final _search = TextEditingController();
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _records = const [];
  String? _message;
  bool _loading = true;
  bool _exporting = false;
  String? _exportCursor;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final result = await _callNewsletterAdmin('adminNewsletterDashboard');
      if (mounted) {
        setState(() => _summary = result);
      }
    } on _NewsletterAdminRequestException catch (error) {
      if (mounted) {
        setState(() => _message =
            error.message ?? 'Audience data is unavailable for this role.');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Audience data is unavailable.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchRecords() async {
    final query = _search.text.trim();
    if (query.isEmpty) return;
    setState(() => _message = null);
    try {
      final data = await _callNewsletterAdmin(
          'adminSearchNewsletterSubscribers', {'query': query});
      if (!mounted) return;
      setState(() => _records = (data['records'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false));
    } on _NewsletterAdminRequestException catch (error) {
      if (!mounted) return;
      setState(
          () => _message = error.message ?? 'Could not search the audience.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not search the audience.');
    }
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final data = await _callNewsletterAdmin(
          'adminExportNewsletterSubscribers', {'cursor': _exportCursor});
      final records = (data['records'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map));
      final csv =
          StringBuffer('email,status,categories,signupSource,subscribedAt\n');
      for (final item in records) {
        csv.writeln([
          item['email'],
          item['status'],
          (item['categories'] as List? ?? const []).join('|'),
          item['signupSource'],
          item['subscribedAt']
        ].map(newsletterCsvCell).join(','));
      }
      await Clipboard.setData(ClipboardData(text: csv.toString()));
      if (mounted) {
        setState(() {
          _exportCursor = data['nextCursor'] as String?;
          _message =
              '${records.length} active subscriber records copied as CSV.'
              '${_exportCursor == null ? ' Export complete.' : ' More records are available; export the next page.'}';
        });
      }
    } on _NewsletterAdminRequestException catch (error) {
      if (mounted) {
        setState(
            () => _message = error.message ?? 'You do not have export access.');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not export the audience.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final summary = _summary ?? const <String, dynamic>{};
    return ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Newsletter & Audience',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text(
          'Consent-led marketing audience. Subscriber details are available only through authorised server calls.',
          style: TextStyle(color: Colors.white.withValues(alpha: .7))),
      const SizedBox(height: 20),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _metric('Active subscribers', summary['active']),
        _metric('New in 30 days', summary['newLast30Days']),
        _metric('Unsubscribed', summary['unsubscribed']),
        _metric('New vs prior 30 days', summary['growth']),
      ]),
      const SizedBox(height: 16),
      const Text('Acquisition sources (all subscribers)'),
      Text('${summary['sources'] ?? {}}'),
      const SizedBox(height: 8),
      const Text('Subscribed interests'),
      Text('${summary['categories'] ?? {}}'),
      const SizedBox(height: 24),
      TextField(
          controller: _search,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _searchRecords(),
          decoration: InputDecoration(
              labelText: 'Find a subscriber by email',
              suffixIcon: IconButton(
                  icon: const Icon(Icons.search), onPressed: _searchRecords),
              border: const OutlineInputBorder())),
      const SizedBox(height: 12),
      Wrap(spacing: 12, children: [
        FilledButton.icon(
            onPressed: _searchRecords,
            icon: const Icon(Icons.search),
            label: const Text('Search')),
        OutlinedButton.icon(
            onPressed: _exporting ? null : _export,
            icon: const Icon(Icons.download_rounded),
            label: Text(_exportCursor == null
                ? 'Export active audience'
                : 'Export next page'))
      ]),
      if (_message != null) ...[const SizedBox(height: 16), Text(_message!)],
      if (_records.isNotEmpty) ...[
        const SizedBox(height: 22),
        const Text('Search results',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 8),
        ..._records.map((record) => Card(
            child: ListTile(
                title: Text('${record['email'] ?? ''}'),
                subtitle: Text(
                    '${record['status']} • ${(record['categories'] as List? ?? const []).join(', ')} • ${record['signupSource'] ?? ''}')))),
      ],
    ]);
  }

  Widget _metric(String label, Object? value) => Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$value',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label)
      ]));
}
