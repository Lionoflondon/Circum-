import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../sender_mobile/design_system/sender_design_system.dart';
import '../sender_mobile/sender_finance.dart';
import 'business_models.dart';
import 'business_repository.dart';
import 'business_view.dart';

class BusinessAccessView extends StatefulWidget {
  final BusinessRepository? repository;
  final SenderPaymentProfileRepository? paymentProfileRepository;

  const BusinessAccessView({
    super.key,
    this.repository,
    this.paymentProfileRepository,
  });

  @override
  State<BusinessAccessView> createState() => _BusinessAccessViewState();
}

class _BusinessAccessViewState extends State<BusinessAccessView> {
  late final BusinessRepository _repository;
  bool _loading = true;
  String? _error;
  List<BusinessAccount> _accounts = const [];

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseBusinessRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accounts = await _repository.loadAccounts();
      if (!mounted) return;
      setState(() => _accounts = accounts);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _error == null && _accounts.isNotEmpty) {
      return BusinessView(
        repository: _repository,
        paymentProfileRepository: widget.paymentProfileRepository,
      );
    }
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        backgroundColor: AppTokens.background,
        appBar: AppBar(
          title: const Text('Business'),
          backgroundColor: AppTokens.background,
          foregroundColor: AppTokens.text,
          elevation: 0,
        ),
        body: SafeArea(
          child: _loading
              ? const _BusinessAccessLoading()
              : _error != null
                  ? AppEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Business is unavailable',
                      body: _error!,
                      actionLabel: 'Retry',
                      onAction: _load,
                    )
                  : _BusinessEntry(
                      repository: _repository,
                      onWorkspaceReady: _load,
                    ),
        ),
      ),
    );
  }
}

class _BusinessEntry extends StatelessWidget {
  final BusinessRepository repository;
  final VoidCallback onWorkspaceReady;

  const _BusinessEntry({
    required this.repository,
    required this.onWorkspaceReady,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        AppGlassContainer(
          accent: AppTokens.primary,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Business for Circum',
                style: GoogleFonts.dmSerifDisplay(
                  color: AppTokens.text,
                  fontSize: 34,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Manage company deliveries, teams, invoicing and analytics from one dedicated workspace.',
                style: TextStyle(color: AppTokens.mutedText, height: 1.45),
              ),
              const SizedBox(height: 18),
              for (final benefit in const [
                'Separate personal and business deliveries',
                'Team management',
                'Business invoicing',
                'Delivery analytics',
                'Health+',
                'Gifts',
                'Vanguard',
                'Business payment methods',
              ])
                _BenefitLine(benefit),
              const SizedBox(height: 22),
              AppButton(
                label: 'Create Business Account',
                icon: Icons.add_business_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _CreateBusinessScreen(
                      repository: repository,
                      onWorkspaceReady: onWorkspaceReady,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Join Existing Business',
                icon: Icons.numbers_rounded,
                style: AppButtonStyle.secondary,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _JoinBusinessScreen(
                      repository: repository,
                      onWorkspaceReady: onWorkspaceReady,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BenefitLine extends StatelessWidget {
  final String text;
  const _BenefitLine(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppTokens.success, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _CreateBusinessScreen extends StatefulWidget {
  final BusinessRepository repository;
  final VoidCallback onWorkspaceReady;

  const _CreateBusinessScreen({
    required this.repository,
    required this.onWorkspaceReady,
  });

  @override
  State<_CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends State<_CreateBusinessScreen> {
  final _company = TextEditingController();
  final _type = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _vat = TextEditingController();
  final _size = TextEditingController();
  var _step = 0;
  var _terms = false;
  var _working = false;
  String? _error;
  BusinessCreatedResult? _created;

  @override
  void dispose() {
    _company.dispose();
    _type.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _vat.dispose();
    _size.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final created = await widget.repository.createBusinessAccount(
        BusinessCreateDraft(
          companyName: _company.text,
          businessType: _type.text,
          businessEmail: _email.text,
          businessPhone: _phone.text,
          businessAddress: _address.text,
          vatNumber: _vat.text,
          businessSize: _size.text,
          acceptTerms: _terms,
        ),
      );
      if (!mounted) return;
      setState(() => _created = created);
      widget.onWorkspaceReady();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_created != null) {
      return _BusinessCreatedScreen(
        result: _created!,
        onOpenDashboard: () {
          widget.onWorkspaceReady();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (_) => BusinessView(repository: widget.repository),
            ),
            (route) => route.isFirst,
          );
        },
      );
    }
    return _AccessScaffold(
      title: 'Create Business Account',
      child: AppGlassContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Step ${_step + 1} of 2',
                style: const TextStyle(color: AppTokens.primaryLight)),
            const SizedBox(height: 14),
            if (_step == 0) ...[
              _AccessField(label: 'Company Name', controller: _company),
              _AccessField(label: 'Business Type', controller: _type),
              _AccessField(
                  label: 'Business Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress),
              _AccessField(
                  label: 'Business Phone',
                  controller: _phone,
                  keyboardType: TextInputType.phone),
              AppButton(
                label: 'Continue',
                onPressed: () => setState(() => _step = 1),
              ),
            ] else ...[
              _AccessField(label: 'Business Address', controller: _address),
              _AccessField(label: 'VAT Number (optional)', controller: _vat),
              _AccessField(label: 'Business Size', controller: _size),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _terms,
                onChanged: (value) => setState(() => _terms = value ?? false),
                title: const Text('Accept Terms'),
              ),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppTokens.danger)),
                const SizedBox(height: 10),
              ],
              AppButton(
                label: _working ? 'Creating…' : 'Create Business',
                onPressed: _working ? null : _create,
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Back',
                style: AppButtonStyle.quiet,
                onPressed: () => setState(() => _step = 0),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JoinBusinessScreen extends StatefulWidget {
  final BusinessRepository repository;
  final VoidCallback onWorkspaceReady;

  const _JoinBusinessScreen({
    required this.repository,
    required this.onWorkspaceReady,
  });

  @override
  State<_JoinBusinessScreen> createState() => _JoinBusinessScreenState();
}

class _JoinBusinessScreenState extends State<_JoinBusinessScreen> {
  final _code = TextEditingController();
  BusinessCodeLookupResult? _business;
  String? _message;
  bool _working = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    setState(() {
      _working = true;
      _message = null;
      _business = null;
    });
    try {
      final business = await widget.repository.lookupCompanyCode(_code.text);
      if (mounted) setState(() => _business = business);
    } catch (_) {
      if (mounted) setState(() => _message = 'Company not found.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _requestAccess() async {
    final business = _business;
    if (business == null) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final status =
          await widget.repository.requestBusinessAccess(business: business);
      widget.onWorkspaceReady();
      if (!mounted) return;
      setState(() {
        _message = status == 'joined' || status == 'already_member'
            ? 'Access granted. You can open Business now.'
            : 'Request Sent. Waiting for approval.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AccessScaffold(
        title: 'Join Existing Business',
        child: AppGlassContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AccessField(
                label: 'Company Code',
                controller: _code,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
              ),
              AppButton(
                label: _working ? 'Checking…' : 'Continue',
                onPressed: _working ? null : _lookup,
              ),
              if (_business != null) ...[
                const SizedBox(height: 18),
                const Divider(),
                Text(_business!.companyName,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(_business!.businessAddress,
                    style: const TextStyle(color: AppTokens.mutedText)),
                const SizedBox(height: 6),
                Text('Business Status: ${_business!.businessStatus}'),
                Text('Role requested: ${_business!.roleRequested}'),
                const SizedBox(height: 14),
                AppButton(
                  label: 'Request Access',
                  onPressed: _working ? null : _requestAccess,
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 14),
                Text(_message!),
              ],
            ],
          ),
        ),
      );
}

class _BusinessCreatedScreen extends StatelessWidget {
  final BusinessCreatedResult result;
  final VoidCallback onOpenDashboard;

  const _BusinessCreatedScreen({
    required this.result,
    required this.onOpenDashboard,
  });

  @override
  Widget build(BuildContext context) => _AccessScaffold(
        title: 'Business Created ✓',
        child: AppGlassContainer(
          accent: AppTokens.success,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.companyName,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text(
                'Generated Company Code',
                style: TextStyle(color: AppTokens.mutedText),
              ),
              const SizedBox(height: 6),
              SelectableText(
                result.companyCode,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Share this Company Code with employees so they can join your business.',
              ),
              const SizedBox(height: 18),
              AppButton(
                label: 'Open Business Dashboard',
                onPressed: onOpenDashboard,
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Copy Company Code',
                style: AppButtonStyle.secondary,
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: result.companyCode),
                ),
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Share Company Code',
                style: AppButtonStyle.secondary,
                onPressed: () => Share.share(
                  'Join ${result.companyName} on Circum Business with company code ${result.companyCode}.',
                ),
              ),
            ],
          ),
        ),
      );
}

class _AccessScaffold extends StatelessWidget {
  final String title;
  final Widget child;

  const _AccessScaffold({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Theme(
        data: AppTheme.dark(),
        child: Scaffold(
          backgroundColor: AppTokens.background,
          appBar: AppBar(
            title: Text(title),
            backgroundColor: AppTokens.background,
            foregroundColor: AppTokens.text,
            elevation: 0,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              children: [child],
            ),
          ),
        ),
      );
}

class _AccessField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _AccessField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(labelText: label),
        ),
      );
}

class _BusinessAccessLoading extends StatelessWidget {
  const _BusinessAccessLoading();

  @override
  Widget build(BuildContext context) => const Center(
        child: AppGlassContainer(
          constraints: BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2.4),
              SizedBox(height: 16),
              Text('Checking Business access…'),
            ],
          ),
        ),
      );
}
