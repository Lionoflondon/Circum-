import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../health_plus/view/health_plus.dart';
import '../sender_mobile/gift_mode_view.dart';
import '../sender_mobile/sender_booking_canvas.dart';
import '../sender_mobile/sender_finance.dart';
import '../sender_mobile/design_system/sender_design_system.dart';
import 'business_iris_moments.dart';
import 'business_journey_context.dart';
import 'business_models.dart';
import 'business_repository.dart';

const _navy = Color(0xFF07090F);
const _panel = Color(0xFF0D111C);
const _raised = Color(0xFF121729);
const _field = Color(0xFF161B2C);
const _border = Color(0xFF212842);
const _blue = Color(0xFF3B82F6);
const _text = Color(0xFFF5F7FB);
const _muted = Color(0xFF8992AB);
const _mutedDim = Color(0xFF5B6280);
const _success = Color(0xFF22C55E);
const _warning = Color(0xFFF5A623);
const _danger = Color(0xFFF0555B);
const _roth = Color(0xFFC9A227);

class BusinessView extends StatefulWidget {
  final BusinessRepository? repository;
  final SenderPaymentProfileRepository? paymentProfileRepository;
  final VoidCallback? onBookDelivery;
  final VoidCallback? onOpenHealthPlus;
  final VoidCallback? onOpenGifts;

  const BusinessView({
    super.key,
    this.repository,
    this.paymentProfileRepository,
    this.onBookDelivery,
    this.onOpenHealthPlus,
    this.onOpenGifts,
  });

  @override
  State<BusinessView> createState() => _BusinessViewState();
}

class _BusinessViewState extends State<BusinessView> {
  late final BusinessRepository _repository;
  late final SenderPaymentProfileRepository _paymentRepository;
  final _search = TextEditingController();
  BusinessSection _section = BusinessSection.overview;
  BusinessDeliverySegment _deliverySegment = BusinessDeliverySegment.active;
  List<BusinessAccount> _accounts = const [];
  BusinessAccount? _account;
  BusinessWorkspaceData? _workspace;
  SenderPaymentProfile? _paymentProfile;
  List<BusinessAccessRequest> _accessRequests = const [];
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseBusinessRepository();
    _paymentRepository = widget.paymentProfileRepository ??
        FirebaseSenderPaymentProfileRepository();
    final returnParameters = Uri.base.queryParameters;
    if (returnParameters['section'] == 'invoicing') {
      _section = BusinessSection.invoices;
    }
    final returnMessage = switch (returnParameters) {
      {'paymentStatus': 'payment-success'} =>
        'Invoice payment returned securely. Circum is confirming it.',
      {'paymentStatus': 'payment-cancelled'} =>
        'Invoice payment was cancelled. No new charge was made.',
      {'roth_purchase': 'success'} =>
        'Roth purchase returned securely. Circum is confirming it.',
      {'roth_purchase': 'cancelled'} =>
        'Roth purchase was cancelled. No new charge was made.',
      _ => null,
    };
    if (returnMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showMessage(returnMessage);
      });
    }
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({String? accountId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accounts = await _repository.loadAccounts();
      if (accounts.isEmpty) {
        if (!mounted) return;
        setState(() {
          _accounts = const [];
          _account = null;
          _workspace = null;
        });
        return;
      }
      final selected = accounts.firstWhere(
        (item) => item.id == (accountId ?? _account?.id),
        orElse: () => accounts.first,
      );
      final results = await Future.wait<dynamic>([
        _repository.loadWorkspace(selected),
        _paymentRepository.paymentMethods().catchError(
              (_) => SenderPaymentProfile.empty(),
            ),
        _repository.loadPendingAccessRequests(selected).catchError(
              (_) => <BusinessAccessRequest>[],
            ),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _account = selected;
        _workspace = results[0] as BusinessWorkspaceData;
        _paymentProfile = results[1] as SenderPaymentProfile;
        _accessRequests = results[2] as List<BusinessAccessRequest>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectSection(BusinessSection section) {
    setState(() {
      _section = section;
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.dark().copyWith(
      scaffoldBackgroundColor: _navy,
      colorScheme: const ColorScheme.dark(primary: _blue, surface: _panel),
      textTheme: GoogleFonts.interTextTheme(AppTheme.dark().textTheme)
          .apply(bodyColor: _text, displayColor: _text),
    );
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: _navy,
        body: SafeArea(
          child: _loading
              ? const _BusinessLoading()
              : _error != null
                  ? _BusinessFailure(message: _error!, onRetry: _load)
                  : _account == null || _workspace == null
                      ? _BusinessEmpty(onRetry: _load)
                      : RefreshIndicator(
                          onRefresh: () => _load(accountId: _account!.id),
                          color: _blue,
                          backgroundColor: _panel,
                          child: CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(child: _header()),
                              SliverToBoxAdapter(child: _tabs()),
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(22, 0, 22, 32),
                                sliver: SliverToBoxAdapter(child: _content()),
                              ),
                            ],
                          ),
                        ),
        ),
      ),
    );
  }

  Widget _header() {
    final account = _account!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              'CIRCUM · BUSINESS',
              style: GoogleFonts.jetBrainsMono(
                color: _muted,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
          ),
          if (_accounts.length > 1)
            PopupMenuButton<String>(
              color: _raised,
              onSelected: (id) => _load(accountId: id),
              itemBuilder: (_) => _accounts
                  .map((item) =>
                      PopupMenuItem(value: item.id, child: Text(item.name)))
                  .toList(growable: false),
              child: _Pill(icon: Icons.business_rounded, label: account.name),
            )
          else
            _Pill(icon: Icons.business_rounded, label: account.name),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient:
                  const LinearGradient(colors: [_blue, Color(0xFF1E4FBF)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              account.name.isEmpty ? 'B' : account.name[0].toUpperCase(),
              style:
                  GoogleFonts.dmSerifDisplay(fontSize: 21, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Good ${_dayPart()}, ${_shortBusinessName(account.name)}.',
              style: GoogleFonts.dmSerifDisplay(fontSize: 26, height: 1.15),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusPill(
                approved: account.isApproved, label: account.statusLabel),
            if (account.isPatron)
              _Pill(
                icon: Icons.workspace_premium_rounded,
                label: account.patronNumber == null
                    ? 'Patron'
                    : 'Patron #${account.patronNumber.toString().padLeft(3, '0')}',
              ),
          ],
        ),
        if (!account.isApproved) ...[
          const SizedBox(height: 12),
          _VerificationJourney(status: account.status),
        ],
      ]),
    );
  }

  Widget _tabs() {
    const data = <(BusinessSection, IconData, String)>[
      (BusinessSection.overview, Icons.home_rounded, 'Overview'),
      (BusinessSection.deliveries, Icons.local_shipping_rounded, 'Deliveries'),
      (BusinessSection.invoices, Icons.receipt_long_rounded, 'Invoices'),
      (BusinessSection.team, Icons.groups_rounded, 'Team'),
      (BusinessSection.healthPlus, Icons.health_and_safety_rounded, 'Health+'),
      (BusinessSection.gifts, Icons.card_giftcard_rounded, 'Gifts'),
      (BusinessSection.vanguard, Icons.shield_rounded, 'Vanguard'),
      (BusinessSection.analytics, Icons.analytics_rounded, 'Analytics'),
      (
        BusinessSection.finance,
        Icons.account_balance_wallet_rounded,
        'Finance'
      ),
      (BusinessSection.settings, Icons.settings_rounded, 'Settings'),
    ];
    return SizedBox(
      height: 54,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: data.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final item = data[index];
          final selected = _section == item.$1;
          return ChoiceChip(
            key: ValueKey('business-tab-${item.$1.name}'),
            selected: selected,
            onSelected: (_) => _selectSection(item.$1),
            avatar: Icon(item.$2,
                size: 16, color: selected ? const Color(0xFFDCE7FF) : _muted),
            label: Text(item.$3),
            labelStyle: TextStyle(
              color: selected ? const Color(0xFFDCE7FF) : _muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: _panel,
            selectedColor: _blue.withValues(alpha: .14),
            side: BorderSide(
                color: selected ? _blue.withValues(alpha: .5) : _border),
            shape: const StadiumBorder(),
          );
        },
      ),
    );
  }

  Widget _content() {
    switch (_section) {
      case BusinessSection.overview:
        return _overview();
      case BusinessSection.deliveries:
        return _deliveries();
      case BusinessSection.invoices:
        return _invoices();
      case BusinessSection.team:
        return _team();
      case BusinessSection.healthPlus:
        return _productRequests(isHealth: true);
      case BusinessSection.gifts:
        return _productRequests(isHealth: false);
      case BusinessSection.vanguard:
        return _vanguard();
      case BusinessSection.analytics:
        return _analytics();
      case BusinessSection.finance:
        return _finance();
      case BusinessSection.settings:
        return _settings();
    }
  }

  Widget _overview() {
    final data = _workspace!;
    final activeDeliveries =
        data.deliveries.where((item) => item.isActive).length;
    final scheduledDeliveries =
        data.deliveries.where((item) => item.isScheduled).length;
    final vanguardDeliveries =
        data.deliveries.where((item) => item.hasVanguard).length;
    final recentDeliveries = data.deliveries.take(4).toList(growable: false);
    final recentInvoices = data.invoices.take(3).toList(growable: false);
    final teamActivity =
        data.account.teamMembers.take(3).toList(growable: false);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle(
          'Your command centre for deliveries, invoices, team access, Health+, Gifts, Vanguard and operational insights.'),
      _ResponsiveGrid(
        minItemWidth: 150,
        childAspectRatio: 2.15,
        children: [
          _CompactKpiCard(
              label: 'Active Deliveries',
              value: '$activeDeliveries',
              icon: Icons.local_shipping_rounded,
              onTap: () => _selectSection(BusinessSection.deliveries)),
          _CompactKpiCard(
              label: 'Scheduled Deliveries',
              value: '$scheduledDeliveries',
              icon: Icons.event_available_rounded,
              onTap: () => _selectSection(BusinessSection.deliveries)),
          _CompactKpiCard(
              label: 'Deliveries This Month',
              value: '${data.monthlyDeliveries}',
              icon: Icons.calendar_month_rounded,
              onTap: () => _selectSection(BusinessSection.analytics)),
          _CompactKpiCard(
              label: 'Vanguard Deliveries',
              value: '$vanguardDeliveries',
              icon: Icons.shield_rounded,
              onTap: () => _selectSection(BusinessSection.vanguard)),
          _CompactKpiCard(
              label: 'Health+ Requests',
              value: '${data.healthRequests.length}',
              icon: Icons.health_and_safety_rounded,
              onTap: () => _selectSection(BusinessSection.healthPlus)),
          _CompactKpiCard(
              label: 'Gifts Sent',
              value: '${data.giftRequests.length}',
              icon: Icons.card_giftcard_rounded,
              onTap: () => _selectSection(BusinessSection.gifts)),
        ],
      ),
      const _SectionLabel('Quick actions'),
      _ResponsiveGrid(
        minItemWidth: 160,
        childAspectRatio: 2.4,
        children: [
          _ActionTile(
              icon: Icons.local_shipping_rounded,
              title: 'Book a delivery',
              subtitle: 'Use Business billing',
              onTap: _bookDelivery),
          _ActionTile(
              icon: Icons.person_add_alt_1_rounded,
              title: 'Invite teammate',
              subtitle: 'Add role-based access',
              onTap: _inviteMember),
          _ActionTile(
              icon: Icons.health_and_safety_rounded,
              title: 'Health+ request',
              subtitle: 'Start a secure collection',
              onTap: _openHealthPlus),
          _ActionTile(
              icon: Icons.card_giftcard_rounded,
              title: 'Corporate gift',
              subtitle: 'Create a gift order',
              onTap: _openGifts),
        ],
      ),
      const SizedBox(height: 14),
      BusinessIrisMomentsPanel(
        businessName: data.account.name,
        moments: data.account.irisMoments,
        canOperate: data.account.isApproved,
        onAddMoment: _addIrisMoment,
        onSendGift: _openGifts,
        onCreateDelivery: _bookDelivery,
        onScheduleHealthPlus: _openHealthPlus,
      ),
      const _SectionLabel('Recent Deliveries'),
      if (recentDeliveries.isEmpty)
        _EmptyState(
          icon: Icons.local_shipping_outlined,
          message: 'Recent deliveries will appear here.',
          actionLabel: 'Book Delivery',
          onAction: _bookDelivery,
        )
      else
        ...recentDeliveries.map(_deliveryRow),
      const _SectionLabel('Recent Invoices'),
      if (recentInvoices.isEmpty)
        const _EmptyState(
          icon: Icons.receipt_long_outlined,
          message: 'Recent invoices will appear here after billing.',
        )
      else
        ...recentInvoices.map((invoice) =>
            _invoiceRow(invoice, onTap: () => _showInvoiceDetails(invoice))),
      const _SectionLabel('Team Activity'),
      if (teamActivity.isEmpty)
        _EmptyState(
          icon: Icons.groups_outlined,
          message: 'Invite dispatch, finance or viewer teammates.',
          actionLabel: 'Invite Member',
          onAction: _inviteMember,
        )
      else
        ...teamActivity.map(_memberRow),
      const _SectionLabel('Business Notifications'),
      _NotificationSummary(
        enabled: data.account.notificationPreferences,
        pendingInvoices: data.invoices.where((item) => !item.isPaid).length,
        activeDeliveries: activeDeliveries,
      ),
    ]);
  }

  Widget _deliveries() {
    final query = _search.text.trim().toLowerCase();
    final filtered = _workspace!.deliveries.where((item) {
      final segmentMatches = switch (_deliverySegment) {
        BusinessDeliverySegment.active => item.isActive,
        BusinessDeliverySegment.scheduled => item.isScheduled,
        BusinessDeliverySegment.completed => item.isCompleted,
      };
      return segmentMatches &&
          (query.isEmpty ||
              '${item.id} ${item.pickup} ${item.dropoff} ${item.bookedBy}'
                  .toLowerCase()
                  .contains(query));
    }).toList(growable: false);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle(
          'Book, track, rebook and export business movement history.'),
      _PrimaryButton(
          label: 'Book a delivery',
          icon: Icons.add_rounded,
          onTap: _bookDelivery),
      const SizedBox(height: 12),
      _SearchField(
          controller: _search,
          hint: 'Search delivery ID, location or team member',
          onChanged: (_) => setState(() {})),
      const SizedBox(height: 10),
      SegmentedButton<BusinessDeliverySegment>(
        segments: const [
          ButtonSegment(
              value: BusinessDeliverySegment.active, label: Text('Active')),
          ButtonSegment(
              value: BusinessDeliverySegment.scheduled,
              label: Text('Scheduled')),
          ButtonSegment(
              value: BusinessDeliverySegment.completed,
              label: Text('Completed')),
        ],
        selected: {_deliverySegment},
        onSelectionChanged: (value) =>
            setState(() => _deliverySegment = value.first),
        showSelectedIcon: false,
      ),
      const SizedBox(height: 14),
      if (filtered.isEmpty)
        _EmptyState(
            icon: Icons.local_shipping_outlined,
            message: 'No deliveries in this view.',
            actionLabel: 'Book Delivery',
            onAction: _bookDelivery)
      else
        ...filtered.map(_deliveryRow),
      const SizedBox(height: 8),
      _ResponsiveGrid(minItemWidth: 145, childAspectRatio: 3.2, children: [
        _CompactAction(
            label: 'Cancel',
            icon: Icons.cancel_outlined,
            onTap: () => _showMessage(
                'Open Delivery Details to cancel eligible deliveries.')),
        _CompactAction(
            label: 'Delivery Details',
            icon: Icons.info_outline_rounded,
            onTap: () => _showMessage(
                'Select a delivery row to open delivery details.')),
        _CompactAction(
            label: 'Export CSV',
            icon: Icons.table_view_rounded,
            onTap: () =>
                _showMessage('Delivery CSV export is being prepared.')),
      ]),
    ]);
  }

  Widget _invoices() {
    final query = _search.text.trim().toLowerCase();
    final invoices = _workspace!.invoices
        .where((item) =>
            query.isEmpty ||
            '${item.number} ${item.id} ${item.status}'
                .toLowerCase()
                .contains(query))
        .toList(growable: false);
    final paid = _workspace!.invoices.where((item) => item.isPaid).length;
    final due = _workspace!.invoices
        .where((item) => !item.isPaid && !_isOverdue(item))
        .length;
    final overdue = _workspace!.invoices.where(_isOverdue).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle(
          'View invoice history, delivery breakdowns, statements and Roth offsets.'),
      _ResponsiveGrid(minItemWidth: 120, childAspectRatio: 2.4, children: [
        _CompactKpiCard(
            label: 'Paid', value: '$paid', icon: Icons.check_rounded),
        _CompactKpiCard(
            label: 'Due', value: '$due', icon: Icons.schedule_rounded),
        _CompactKpiCard(
            label: 'Overdue',
            value: '$overdue',
            icon: Icons.warning_amber_rounded,
            valueColor: overdue > 0 ? _warning : null),
      ]),
      const SizedBox(height: 12),
      _SearchField(
          controller: _search,
          hint: 'Search invoice number or delivery ID',
          onChanged: (_) => setState(() {})),
      const SizedBox(height: 12),
      if (invoices.isEmpty)
        const _EmptyState(
            icon: Icons.receipt_long_outlined,
            message:
                'Invoices will appear here when your Business account is billed.')
      else
        ...invoices.map((invoice) =>
            _invoiceRow(invoice, onTap: () => _showInvoiceDetails(invoice))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _CompactAction(
            label: 'Download PDF',
            icon: Icons.picture_as_pdf_rounded,
            onTap: () => _showMessage('Select an invoice to download PDF.')),
        _CompactAction(
            label: 'Download CSV',
            icon: Icons.table_view_rounded,
            onTap: () => _showMessage('Invoice CSV export is being prepared.')),
        _CompactAction(
            label: 'VAT Invoices',
            icon: Icons.description_rounded,
            onTap: () => _showMessage('VAT invoices use existing records.')),
        _CompactAction(
            label: 'Statement History',
            icon: Icons.history_rounded,
            onTap: () => _showMessage(
                'Statement history uses your existing invoice records.')),
        _CompactAction(
            label: 'Roth Offset Used',
            icon: Icons.diamond_outlined,
            onTap: () => _showMessage(
                'Roth offsets are shown on each invoice and Finance.')),
        _CompactAction(
            label: 'Payment Method',
            icon: Icons.credit_card_rounded,
            onTap: () =>
                _showMessage('Payment methods are managed in Finance.')),
      ]),
    ]);
  }

  Widget _team() {
    final members = _workspace!.account.teamMembers;
    final active =
        members.where((item) => item['status'] != 'invited').toList();
    final pending =
        members.where((item) => item['status'] == 'invited').toList();
    final canManageCompanyCode = _canManageCompanyCode(_workspace!.account);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle('Invite, suspend and permission team members by role.'),
      if (canManageCompanyCode) ...[
        _companyCodeCard(_workspace!.account),
        const SizedBox(height: 12),
      ],
      _PrimaryButton(
          label: 'Invite teammate',
          icon: Icons.person_add_alt_1_rounded,
          onTap: _inviteMember),
      const SizedBox(height: 12),
      _InformationCard(
        icon: Icons.admin_panel_settings_rounded,
        title: 'Roles and permissions',
        body:
            'Owner, Admin, Dispatcher, Finance and Viewer roles control booking, invoice, team and read-only access.',
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _CompactAction(
            label: 'Permissions',
            icon: Icons.rule_rounded,
            onTap: () =>
                _showMessage('Permissions are applied through team roles.')),
        _CompactAction(
            label: 'Activity Log',
            icon: Icons.manage_history_rounded,
            onTap: () => _showMessage('Team activity log is being prepared.')),
        _CompactAction(
            label: 'Resend Invitation',
            icon: Icons.mark_email_unread_rounded,
            onTap: () =>
                _showMessage('Open a pending invitation to resend it.')),
      ]),
      const _SectionLabel('Active members'),
      if (active.isEmpty)
        const _EmptyState(
            icon: Icons.groups_outlined,
            message: 'No active team members are available.')
      else
        ...active.map(_memberRow),
      const _SectionLabel('Pending invites'),
      if (pending.isEmpty)
        const _EmptyState(
            icon: Icons.mark_email_unread_outlined,
            message: 'No pending invitations.')
      else
        ...pending.map(_memberRow),
      const _SectionLabel('Pending access requests'),
      if (_accessRequests.isEmpty)
        const _EmptyState(
            icon: Icons.person_add_alt_1_outlined,
            message: 'No pending Business access requests.')
      else
        ..._accessRequests.map(_accessRequestRow),
    ]);
  }

  Widget _companyCodeCard(BusinessAccount account) {
    final code = account.companyCode.trim();
    final hasCode = code.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: hasCode ? _blue : _border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.group_add_rounded, color: _blue),
          const SizedBox(width: 10),
          Text('Company code', style: Theme.of(context).textTheme.titleMedium),
        ]),
        const SizedBox(height: 8),
        Text(
          hasCode
              ? 'Share this code with team members so they can request access.'
              : 'Generate a company code so team members can request access.',
          style: const TextStyle(color: _muted, height: 1.35),
        ),
        if (hasCode) ...[
          const SizedBox(height: 10),
          SelectableText(
            code,
            style: GoogleFonts.jetBrainsMono(
              color: _text,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: _working
                ? null
                : () async {
                    if (!hasCode) {
                      await _ensureCompanyCode();
                      return;
                    }
                    await Clipboard.setData(ClipboardData(text: code));
                    _showMessage('Company code copied.');
                  },
            icon: Icon(hasCode ? Icons.copy_rounded : Icons.add_rounded),
            label: Text(hasCode ? 'Copy' : 'Generate code'),
          ),
          if (hasCode)
            OutlinedButton.icon(
              onPressed:
                  _working ? null : () => _ensureCompanyCode(rotate: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Change code'),
            ),
        ]),
      ]),
    );
  }

  bool _canManageCompanyCode(BusinessAccount account) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    final email = (user?.email ?? '').trim().toLowerCase();
    for (final member in account.teamMembers) {
      final role = '${member['role'] ?? ''}'.trim().toLowerCase();
      final status = '${member['status'] ?? 'active'}'.trim().toLowerCase();
      final sameUid = uid.isNotEmpty && member['userId'] == uid;
      final sameEmail = email.isNotEmpty &&
          '${member['email'] ?? ''}'.trim().toLowerCase() == email;
      if ((sameUid || sameEmail) &&
          status != 'removed' &&
          status != 'rejected' &&
          (role == 'owner' || role == 'admin')) {
        return true;
      }
    }
    return false;
  }

  Widget _productRequests({required bool isHealth}) {
    final requests =
        isHealth ? _workspace!.healthRequests : _workspace!.giftRequests;
    final title = isHealth ? 'Health+' : 'Gifts';
    final active = requests
        .where(
            (item) => !const {'completed', 'delivered'}.contains(item.status))
        .length;
    final completed = requests.length - active;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Subtitle(isHealth
          ? 'Create and monitor Health+ business requests with Vanguard included.'
          : 'Create and monitor corporate gift requests without exposing surprise details.'),
      if (!isHealth)
        const _InformationCard(
          icon: Icons.card_giftcard_rounded,
          title: 'Confidential by design',
          body:
              'Your team sees operational status only. Gift contents remain protected for the recipient.',
        ),
      _ResponsiveGrid(
        minItemWidth: 140,
        childAspectRatio: 2.05,
        children: isHealth
            ? [
                _MiniStat(label: 'Active Requests', value: '$active'),
                _MiniStat(
                    label: 'Scheduled Collections',
                    value:
                        '${requests.where((item) => item.status == 'scheduled').length}'),
                _MiniStat(label: 'Completed Requests', value: '$completed'),
                _MiniStat(
                    label: 'Priority Deliveries',
                    value:
                        '${requests.where((item) => item.status.contains('priority')).length}'),
              ]
            : [
                _MiniStat(label: 'Active Orders', value: '$active'),
                _MiniStat(
                    label: 'Awaiting Approval',
                    value:
                        '${requests.where((item) => item.status.contains('approval')).length}'),
                _MiniStat(label: 'Completed Gifts', value: '$completed'),
                _MiniStat(
                    label: 'Recipient Status',
                    value:
                        '${requests.where((item) => item.status.contains('recipient')).length}'),
              ],
      ),
      const SizedBox(height: 14),
      if (requests.isEmpty)
        _EmptyState(
            icon: isHealth
                ? Icons.health_and_safety_outlined
                : Icons.card_giftcard_outlined,
            message: 'No $title requests yet.',
            actionLabel:
                isHealth ? 'Contact Health+ Team' : 'Reorder Previous Gift',
            onAction: isHealth ? _openHealthPlus : _openGifts)
      else
        ...requests
            .take(10)
            .map((item) => _requestRow(item, isHealth: isHealth)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (isHealth) ...[
          _CompactAction(
              label: 'Medical Chain of Custody',
              icon: Icons.verified_user_rounded,
              onTap: () => _showMessage(
                  'Chain of custody follows each Health+ request.')),
          _CompactAction(
              label: 'Contact Health+ Team',
              icon: Icons.support_agent_rounded,
              onTap: _openHealthPlus),
        ] else ...[
          _CompactAction(
              label: 'Gift History',
              icon: Icons.history_rounded,
              onTap: () => _showMessage('Gift history uses existing orders.')),
          _CompactAction(
              label: 'Reorder Previous Gift',
              icon: Icons.replay_rounded,
              onTap: _openGifts),
        ],
      ]),
      const SizedBox(height: 8),
      _PrimaryButton(
        label: isHealth ? 'New Health+ request' : 'Start a corporate gift',
        icon: Icons.add_rounded,
        onTap: isHealth ? _openHealthPlus : _openGifts,
      ),
    ]);
  }

  Widget _vanguard() {
    final protected = _workspace!.deliveries
        .where((item) => item.hasVanguard)
        .toList(growable: false);
    final activeProtected = protected.where((item) => !item.isCompleted).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle('Review sensitive deliveries and Vanguard-covered jobs.'),
      const _InformationCard(
        icon: Icons.shield_rounded,
        title: 'Vanguard assurance',
        body:
            'Higher-trust riders, stronger verification and a full audit trail for jobs that need careful handling. Vanguard is delivery assurance, not insurance.',
        accented: true,
      ),
      _ResponsiveGrid(minItemWidth: 150, childAspectRatio: 2.15, children: [
        _CompactKpiCard(
            label: 'Protected Deliveries',
            value: '${protected.length}',
            icon: Icons.shield_rounded),
        _CompactKpiCard(
            label: 'Active Protection',
            value: '$activeProtected',
            icon: Icons.lock_rounded),
        _CompactKpiCard(
            label: 'Incident Reports',
            value:
                '${protected.where((item) => item.status.contains('issue') || item.status.contains('dispute')).length}',
            icon: Icons.report_problem_outlined),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _CompactAction(
            label: 'Audit Trail',
            icon: Icons.manage_search_rounded,
            onTap: () => _showMessage('Open a protected delivery for audit.')),
        _CompactAction(
            label: 'Signature Verification',
            icon: Icons.draw_rounded,
            onTap: () => _showMessage(
                'Signature verification appears on protected delivery records.')),
        _CompactAction(
            label: 'Delivery Timeline',
            icon: Icons.timeline_rounded,
            onTap: () => _showMessage('Select a delivery to view timeline.')),
        _CompactAction(
            label: 'Chain of Custody',
            icon: Icons.hub_rounded,
            onTap: () => _showMessage(
                'Chain of custody follows each Vanguard delivery.')),
      ]),
      const SizedBox(height: 12),
      if (protected.isEmpty)
        const _EmptyState(
            icon: Icons.shield_outlined,
            message: 'Vanguard-covered deliveries will appear here.')
      else
        ...protected.map(_deliveryRow),
    ]);
  }

  Widget _analytics() {
    final completed =
        _workspace!.deliveries.where((item) => item.isCompleted).toList();
    final deliveries = _workspace!.deliveries;
    final timed = completed.where((item) => item.duration != null).toList();
    final averageMinutes = timed.isEmpty
        ? 0
        : timed.fold<int>(0, (sum, item) => sum + item.duration!.inMinutes) ~/
            timed.length;
    final categories = <String, int>{};
    final pickupLocations = <String, int>{};
    final dropoffLocations = <String, int>{};
    final monthlyCounts = <String, int>{};
    for (final item in deliveries) {
      categories[item.category] = (categories[item.category] ?? 0) + 1;
      if (item.pickup.isNotEmpty) {
        pickupLocations[item.pickup] = (pickupLocations[item.pickup] ?? 0) + 1;
      }
      if (item.dropoff.isNotEmpty) {
        dropoffLocations[item.dropoff] =
            (dropoffLocations[item.dropoff] ?? 0) + 1;
      }
      final date = item.createdAt ?? item.scheduledAt;
      if (date != null) {
        final key = DateFormat('MMM').format(date);
        monthlyCounts[key] = (monthlyCounts[key] ?? 0) + 1;
      }
    }
    final monthlySpend = _workspace!.deliveries.where((item) {
      final date = item.createdAt;
      final now = DateTime.now();
      return date != null && date.year == now.year && date.month == now.month;
    }).fold<double>(0, (sum, item) => sum + item.amount);
    final successRate = deliveries.isEmpty
        ? 0
        : ((completed.length / deliveries.length) * 100).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle(
          'Clear operational answers drawn from your delivery history.'),
      _ResponsiveGrid(minItemWidth: 210, childAspectRatio: 1.7, children: [
        _MetricChartCard(
            title: 'Monthly Spend',
            value: _gbp(monthlySpend),
            bars: _amountBars(deliveries)),
        _MetricChartCard(
            title: 'Deliveries by Month',
            value: '${deliveries.length}',
            bars: monthlyCounts),
        _MetricListCard(
            title: 'Spend by Department',
            items: _topEntries(categories),
            empty: 'No department data yet.'),
        _MetricChartCard(
            title: 'Delivery Success Rate',
            value: '$successRate%',
            bars: {'Completed': completed.length, 'Total': deliveries.length}),
        _MetricListCard(
            title: 'Delivery Types',
            items: _topEntries(categories),
            empty: 'Delivery types will appear here.'),
        _MetricChartCard(
            title: 'Average Delivery Time',
            value: averageMinutes == 0 ? 'N/A' : '$averageMinutes min',
            bars: {'Avg': averageMinutes}),
        _MetricListCard(
            title: 'Top Pickup Locations',
            items: _topEntries(pickupLocations),
            empty: 'Pickup locations will appear here.'),
        _MetricListCard(
            title: 'Top Drop-off Locations',
            items: _topEntries(dropoffLocations),
            empty: 'Drop-off locations will appear here.'),
      ]),
      const SizedBox(height: 14),
      _SecondaryButton(
          label: 'Export analytics',
          icon: Icons.download_rounded,
          onTap: () => _showMessage('Analytics export is being prepared.')),
    ]);
  }

  Widget _finance() {
    final profile = _paymentProfile ?? SenderPaymentProfile.empty();
    final methods =
        senderOrderedPaymentOptions(profile, includeAddMethod: false);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle(
          'Your business financial home, powered by the existing Circum Finance Engine.'),
      _ResponsiveGrid(minItemWidth: 165, childAspectRatio: 2.1, children: [
        _CompactKpiCard(
            label: 'Outstanding Balance',
            value: _gbp(_workspace!.outstandingBalance),
            icon: Icons.account_balance_wallet_rounded),
        _CompactKpiCard(
            label: 'Roth Balance',
            value: _workspace!.wallet.rothBalance.toStringAsFixed(2),
            valueColor: _roth,
            icon: Icons.diamond_outlined),
        _CompactKpiCard(
            label: 'Current Balance',
            value: _gbp(_workspace!.outstandingBalance),
            icon: Icons.payments_rounded),
        _CompactKpiCard(
            label: 'Outstanding Invoices',
            value:
                '${_workspace!.invoices.where((item) => !item.isPaid).length}',
            icon: Icons.receipt_long_rounded),
        _CompactKpiCard(
            label: 'Roth Offset Used',
            value: _gbp(_workspace!.wallet.lifetimeOffset),
            valueColor: _roth,
            icon: Icons.savings_rounded),
      ]),
      const _SectionLabel('Payment Methods'),
      if (methods.isEmpty)
        const _EmptyState(
            icon: Icons.credit_card_off_rounded,
            message: 'No shared payment methods are available.')
      else
        ...methods.map((item) => _SimpleRow(
              icon: _paymentIcon(item.type),
              title: item.title,
              subtitle: item.isDefault
                  ? 'Default payment method'
                  : 'Available at checkout',
            )),
      const _SimpleRow(
        icon: Icons.diamond_outlined,
        title: 'Roth',
        subtitle: 'Available for full or split invoice payment',
      ),
      const _SectionLabel('Invoices & statements'),
      ..._workspace!.invoices.take(4).map(_invoiceRow),
      if (_workspace!.invoices.isEmpty)
        const _EmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'No invoice or statement history yet.'),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _CompactAction(
            label: 'Billing History',
            icon: Icons.history_rounded,
            onTap: () => _selectSection(BusinessSection.invoices)),
        _CompactAction(
            label: 'Spending Trends',
            icon: Icons.show_chart_rounded,
            onTap: () => _selectSection(BusinessSection.analytics)),
        _CompactAction(
            label: 'Export Statements',
            icon: Icons.download_rounded,
            onTap: () => _showMessage('Statement export is being prepared.')),
      ]),
    ]);
  }

  Widget _settings() {
    final account = _account!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle(
          'Manage your Business details, billing, preferences and connected products.'),
      const _SectionLabel('Business Profile'),
      _SettingsForm(account: account, working: _working, onSave: _saveSettings),
      const _SectionLabel('Addresses'),
      _SimpleRow(
        icon: Icons.location_on_outlined,
        title: 'Default pickup address',
        subtitle: account.defaultPickupAddress.isEmpty
            ? 'Add a default pickup address'
            : account.defaultPickupAddress,
      ),
      const _SectionLabel('Payment Methods'),
      _SimpleRow(
        icon: Icons.credit_card_rounded,
        title: 'Business payment methods',
        subtitle: (_paymentProfile?.methods.isEmpty ?? true)
            ? 'No saved method'
            : '${_paymentProfile!.methods.length} saved method${_paymentProfile!.methods.length == 1 ? '' : 's'}',
      ),
      const _SectionLabel('Connected products'),
      ...[
        ('Business', true),
        (
          'Health+',
          account.connectedProducts.contains('health+') ||
              _workspace!.healthRequests.isNotEmpty
        ),
        (
          'Gifts',
          account.connectedProducts.contains('gifts') ||
              _workspace!.giftRequests.isNotEmpty
        ),
      ].map((item) => _SimpleRow(
            icon: item.$2
                ? Icons.check_circle_rounded
                : Icons.add_circle_outline_rounded,
            title: item.$1,
            subtitle: item.$2 ? 'Joined' : 'Available',
          )),
      const _SectionLabel('Notification'),
      ...const [
        'Deliveries',
        'Invoices',
        'Health+',
        'Gifts',
        'Finance',
        'Team',
        'System'
      ].map((label) {
        final enabled =
            account.notificationPreferences[label.toLowerCase()] != false;
        return SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 2),
          title: Text(label,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          value: enabled,
          onChanged: (value) =>
              _saveNotificationPreference(label.toLowerCase(), value),
        );
      }),
    ]);
  }

  Widget _deliveryRow(BusinessDelivery item) => _OperationalRow(
        icon: item.hasVanguard
            ? Icons.shield_rounded
            : Icons.local_shipping_rounded,
        title:
            '${item.pickup.isEmpty ? 'Pickup' : item.pickup} → ${item.dropoff.isEmpty ? 'Drop-off' : item.dropoff}',
        subtitle: [
          item.id,
          item.vehicle,
          if (item.bookedBy.isNotEmpty) 'Booked by ${item.bookedBy}'
        ].where((value) => value.isNotEmpty).join(' · '),
        amount: item.amount > 0 ? _gbp(item.amount) : null,
        status: _statusLabel(item.status),
      );

  Widget _invoiceRow(BusinessInvoice item, {VoidCallback? onTap}) =>
      _OperationalRow(
        icon: Icons.receipt_long_rounded,
        title: 'Invoice · ${item.number}',
        subtitle:
            '${item.deliveryCount} deliveries${item.rothApplied > 0 ? ' · Roth −${_gbp(item.rothApplied)}' : ''}',
        amount: _gbp(item.balanceDue > 0 ? item.balanceDue : item.total),
        status: item.isPaid ? 'Paid' : 'Due',
        onTap: onTap,
      );

  Widget _requestRow(BusinessRequestSummary item, {required bool isHealth}) =>
      _OperationalRow(
        icon: isHealth
            ? Icons.health_and_safety_rounded
            : Icons.card_giftcard_rounded,
        title: item.title,
        subtitle: item.id,
        status: _statusLabel(item.status),
      );

  Widget _memberRow(Map<String, dynamic> member) {
    final name = '${member['name'] ?? member['email'] ?? 'Team member'}'.trim();
    final role = '${member['role'] ?? 'member'}'.trim();
    return _OperationalRow(
      icon: Icons.person_rounded,
      title: name,
      subtitle:
          '${_title(role)} · ${_title('${member['status'] ?? 'active'}')}',
      trailing: PopupMenuButton<String>(
        color: _raised,
        onSelected: (action) => _handleMemberAction(member, action),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'role', child: Text('Change role')),
          PopupMenuItem(value: 'resend', child: Text('Resend invitation')),
          PopupMenuItem(value: 'suspend', child: Text('Suspend')),
          PopupMenuItem(value: 'remove', child: Text('Remove')),
        ],
      ),
    );
  }

  Widget _accessRequestRow(BusinessAccessRequest request) => _OperationalRow(
        icon: Icons.person_add_alt_1_rounded,
        title: request.name.trim().isEmpty ? request.email : request.name,
        subtitle:
            '${request.email} · Requested ${_title(request.roleRequested)}',
        status: _title(request.status),
        trailing: Wrap(spacing: 6, children: [
          IconButton(
            tooltip: 'Approve request',
            onPressed: () => _handleAccessRequest(request, true),
            icon: const Icon(Icons.check_circle_rounded, color: _success),
          ),
          IconButton(
            tooltip: 'Reject request',
            onPressed: () => _handleAccessRequest(request, false),
            icon: const Icon(Icons.cancel_rounded, color: _danger),
          ),
        ]),
      );

  void _bookDelivery() {
    if (!_account!.isApproved) {
      _showMessage('Business verification must be complete before booking.');
      return;
    }
    final callback = widget.onBookDelivery;
    if (callback != null) {
      callback();
      return;
    }
    _pushBusinessJourney(
      type: BusinessJourneyType.delivery,
      routeName: '/sender-mobile/business/delivery',
      child: const SenderBookingCanvas(),
    );
  }

  void _openHealthPlus() {
    final callback = widget.onOpenHealthPlus;
    if (callback != null) {
      callback();
      return;
    }
    _pushBusinessJourney(
      type: BusinessJourneyType.healthPlus,
      routeName: '/sender-mobile/business/health-plus',
      child: const HealthPlusView(),
    );
  }

  void _openGifts() {
    final callback = widget.onOpenGifts;
    if (callback != null) {
      callback();
      return;
    }
    _pushBusinessJourney(
      type: BusinessJourneyType.gifts,
      routeName: '/sender-mobile/business/gifts',
      child: const GiftModeView(),
    );
  }

  void _pushBusinessJourney({
    required BusinessJourneyType type,
    required String routeName,
    required Widget child,
  }) {
    final journey = BusinessJourneyContext.forAccount(_account!, type);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: routeName, arguments: journey.toMap()),
        builder: (_) => BusinessJourneyScope(journey: journey, child: child),
      ),
    );
  }

  Future<void> _inviteMember() async {
    final email = TextEditingController();
    var role = 'dispatcher';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          backgroundColor: _raised,
          title: const Text('Invite teammate'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const ['owner', 'admin', 'dispatcher', 'finance', 'viewer']
                  .map((item) =>
                      DropdownMenuItem(value: item, child: Text(_title(item))))
                  .toList(growable: false),
              onChanged: (value) => setDialogState(() => role = value ?? role),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Send invite')),
          ],
        );
      }),
    );
    if (approved != true) return;
    try {
      await _repository.inviteMember(
          account: _account!, email: email.text, role: role);
      await _load(accountId: _account!.id);
      _showMessage('Team invitation saved.');
    } catch (error) {
      _showMessage('Invitation failed: $error');
    }
  }

  Future<void> _addIrisMoment() async {
    final moment = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const BusinessMomentDialog(),
    );
    if (moment == null) return;
    try {
      await _repository.addIrisMoment(account: _account!, moment: moment);
      await _load(accountId: _account!.id);
      _showMessage('IRIS Moment added.');
    } catch (error) {
      _showMessage('IRIS Moment could not be saved: $error');
    }
  }

  Future<void> _handleMemberAction(
      Map<String, dynamic> member, String action) async {
    if (action == 'role') {
      final role = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          backgroundColor: _raised,
          title: const Text('Change role'),
          children: const ['owner', 'admin', 'dispatcher', 'finance', 'viewer']
              .map((item) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, item),
                  child: Text(_title(item))))
              .toList(growable: false),
        ),
      );
      if (role == null) return;
      await _repository.updateMember(
          account: _account!, member: member, role: role);
    } else if (action == 'resend') {
      _showMessage('Invitation resent.');
      return;
    } else if (action == 'suspend') {
      await _repository.updateMember(
          account: _account!, member: member, status: 'suspended');
    } else {
      final confirmed = await _confirm('Remove team member?',
          'They will lose access to this Business workspace.');
      if (!confirmed) return;
      await _repository.updateMember(
          account: _account!, member: member, remove: true);
    }
    await _load(accountId: _account!.id);
    _showMessage('Team access updated.');
  }

  Future<void> _handleAccessRequest(
      BusinessAccessRequest request, bool approved) async {
    try {
      await _repository.reviewAccessRequest(
        account: _account!,
        request: request,
        approved: approved,
      );
      await _load(accountId: _account!.id);
      _showMessage(
          approved ? 'Business access approved.' : 'Request rejected.');
    } catch (error) {
      _showMessage('Access request could not be updated: $error');
    }
  }

  Future<void> _showInvoiceDetails(BusinessInvoice invoice) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _raised,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Invoice ${invoice.number}',
                  style: GoogleFonts.dmSerifDisplay(fontSize: 24)),
              const SizedBox(height: 16),
              _DetailLine(label: 'Total', value: _gbp(invoice.total)),
              _DetailLine(
                  label: 'Outstanding', value: _gbp(invoice.balanceDue)),
              _DetailLine(label: 'Status', value: _title(invoice.status)),
              _DetailLine(
                  label: 'Deliveries', value: '${invoice.deliveryCount}'),
              if (invoice.paymentReference.isNotEmpty)
                _DetailLine(
                    label: 'Payment reference',
                    value: invoice.paymentReference),
              const SizedBox(height: 16),
              if (!invoice.isPaid)
                _PrimaryButton(
                    label: 'Pay Invoice',
                    icon: Icons.lock_rounded,
                    onTap: () async {
                      Navigator.pop(context);
                      await _chooseInvoicePayment(invoice);
                    }),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _SecondaryButton(
                        label: 'Download PDF',
                        icon: Icons.picture_as_pdf_rounded,
                        onTap: () =>
                            _showMessage('Invoice PDF is being prepared.'))),
                const SizedBox(width: 8),
                Expanded(
                    child: _SecondaryButton(
                        label: 'Download CSV',
                        icon: Icons.table_view_rounded,
                        onTap: () =>
                            _showMessage('Invoice CSV is being prepared.'))),
              ]),
            ]),
      ),
    );
  }

  Future<void> _chooseInvoicePayment(BusinessInvoice invoice) async {
    final request = await showModalBottomSheet<_BusinessPaymentRequest>(
      context: context,
      backgroundColor: _raised,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BusinessInvoicePaymentSheet(
        invoice: invoice,
        availableRoth: _workspace!.wallet.rothBalance,
        profile: _paymentProfile ?? SenderPaymentProfile.empty(),
      ),
    );
    if (request == null) return;
    try {
      setState(() => _working = true);
      final result = await _repository.payInvoice(
        account: _account!,
        invoice: invoice,
        useRoth: request.useRoth,
        paymentMethod: request.paymentMethod,
      );
      if (result.paid) {
        await _load(accountId: _account!.id);
        _showMessage('Invoice paid with Roth.');
        return;
      }
      final uri = result.checkoutUrl;
      if (uri == null ||
          !await launchUrl(
            uri,
            mode: kIsWeb
                ? LaunchMode.platformDefault
                : LaunchMode.externalApplication,
            webOnlyWindowName: kIsWeb ? '_self' : null,
          )) {
        throw StateError('Secure payment could not open.');
      }
    } catch (error) {
      _showMessage('Invoice payment could not start: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveSettings(BusinessAccount account) async {
    setState(() => _working = true);
    try {
      await _repository.saveAccount(account);
      await _load(accountId: account.id);
      _showMessage('Business settings saved.');
    } catch (error) {
      _showMessage('Settings could not be saved: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _ensureCompanyCode({bool rotate = false}) async {
    final account = _account;
    if (account == null || _working) return;
    setState(() => _working = true);
    try {
      final code =
          await _repository.ensureCompanyCode(account: account, rotate: rotate);
      if (code.isEmpty) {
        _showMessage('Company code could not be retrieved.');
        return;
      }
      await _load(accountId: account.id);
      _showMessage(rotate ? 'Company code changed.' : 'Company code ready.');
    } catch (error) {
      _showMessage('Company code could not be retrieved: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveNotificationPreference(String key, bool value) async {
    final account = _account!;
    final updated = BusinessAccount(
      id: account.id,
      name: account.name,
      status: account.status,
      contactName: account.contactName,
      contactEmail: account.contactEmail,
      phone: account.phone,
      billingEmail: account.billingEmail,
      businessAddress: account.businessAddress,
      companyNumber: account.companyNumber,
      companyCode: account.companyCode,
      defaultPickupAddress: account.defaultPickupAddress,
      teamMembers: account.teamMembers,
      connectedProducts: account.connectedProducts,
      notificationPreferences: {...account.notificationPreferences, key: value},
      paymentPreferences: account.paymentPreferences,
    );
    await _saveSettings(updated);
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _raised,
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm')),
          ],
        ),
      ) ??
      false;
}

class _SettingsForm extends StatefulWidget {
  final BusinessAccount account;
  final bool working;
  final ValueChanged<BusinessAccount> onSave;

  const _SettingsForm(
      {required this.account, required this.working, required this.onSave});

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _BusinessPaymentRequest {
  final bool useRoth;
  final String paymentMethod;

  const _BusinessPaymentRequest({
    required this.useRoth,
    required this.paymentMethod,
  });
}

class _BusinessInvoicePaymentSheet extends StatefulWidget {
  final BusinessInvoice invoice;
  final double availableRoth;
  final SenderPaymentProfile profile;

  const _BusinessInvoicePaymentSheet({
    required this.invoice,
    required this.availableRoth,
    required this.profile,
  });

  @override
  State<_BusinessInvoicePaymentSheet> createState() =>
      _BusinessInvoicePaymentSheetState();
}

class _BusinessInvoicePaymentSheetState
    extends State<_BusinessInvoicePaymentSheet> {
  late bool _useRoth;
  late List<SenderPaymentProfileOption> _methods;
  SenderPaymentProfileOption? _selected;

  @override
  void initState() {
    super.initState();
    _useRoth = widget.availableRoth > 0;
    _methods = senderOrderedPaymentOptions(
      widget.profile,
      includeAddMethod: false,
    );
    _selected = _methods.isEmpty ? null : _methods.first;
  }

  BusinessInvoicePaymentPlan get _plan => BusinessInvoicePaymentPlan.calculate(
        total: widget.invoice.balanceDue,
        availableRoth: widget.availableRoth,
        applyRoth: _useRoth,
      );

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final needsCard = plan.cardAmount > 0;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            22, 4, 22, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Pay Invoice',
              style: GoogleFonts.dmSerifDisplay(fontSize: 25),
            ),
          ),
          const SizedBox(height: 16),
          _DetailLine(label: 'Total invoice', value: _gbp(plan.total)),
          _DetailLine(
              label: 'Available Roth',
              value: plan.availableRoth.toStringAsFixed(2)),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Apply Roth',
                style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text(
                'The Finance Engine applies the best available amount.'),
            value: _useRoth,
            onChanged: widget.availableRoth <= 0
                ? null
                : (value) => setState(() => _useRoth = value),
          ),
          _DetailLine(
              label: 'Roth applied',
              value: plan.rothApplied.toStringAsFixed(2)),
          _DetailLine(label: 'Remaining', value: _gbp(plan.cardAmount)),
          if (needsCard) ...[
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Pay remaining with',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 8),
            if (_methods.isEmpty)
              const _EmptyState(
                icon: Icons.credit_card_off_rounded,
                message: 'Add a payment method before paying the remainder.',
              )
            else
              ..._methods.map((method) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => setState(() => _selected = method),
                    leading: Icon(_paymentIcon(method.type)),
                    title: Text(method.title),
                    subtitle: method.isDefault ? const Text('Default') : null,
                    trailing: _selected == method
                        ? const Icon(Icons.check_circle_rounded, color: _blue)
                        : const Icon(Icons.circle_outlined, color: _muted),
                  )),
          ] else
            const _SimpleRow(
              icon: Icons.diamond_outlined,
              title: 'Roth',
              subtitle: 'Roth covers this invoice in full',
            ),
          const SizedBox(height: 14),
          _PrimaryButton(
            label: plan.isRothOnly
                ? 'Pay with Roth'
                : plan.isSplit
                    ? 'Continue with split payment'
                    : 'Continue to secure payment',
            icon: Icons.lock_rounded,
            onTap: needsCard && _selected == null
                ? null
                : () => Navigator.pop(
                      context,
                      _BusinessPaymentRequest(
                        useRoth: _useRoth,
                        paymentMethod: _paymentMethodValue(_selected),
                      ),
                    ),
          ),
        ]),
      ),
    );
  }
}

class _SettingsFormState extends State<_SettingsForm> {
  late final TextEditingController name;
  late final TextEditingController contact;
  late final TextEditingController phone;
  late final TextEditingController address;
  late final TextEditingController company;
  late final TextEditingController billing;
  late final TextEditingController pickup;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    name = TextEditingController(text: account.name);
    contact = TextEditingController(text: account.contactName);
    phone = TextEditingController(text: account.phone);
    address = TextEditingController(text: account.businessAddress);
    company = TextEditingController(text: account.companyNumber);
    billing = TextEditingController(text: account.billingEmail);
    pickup = TextEditingController(text: account.defaultPickupAddress);
  }

  @override
  void dispose() {
    name.dispose();
    contact.dispose();
    phone.dispose();
    address.dispose();
    company.dispose();
    billing.dispose();
    pickup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        _BusinessField(label: 'Business name', controller: name),
        _BusinessField(label: 'Contact name', controller: contact),
        _BusinessField(
            label: 'Phone',
            controller: phone,
            keyboardType: TextInputType.phone),
        _BusinessField(label: 'Business address', controller: address),
        _BusinessField(label: 'Company number', controller: company),
        _BusinessField(
            label: 'Billing email',
            controller: billing,
            keyboardType: TextInputType.emailAddress),
        _BusinessField(label: 'Default pickup', controller: pickup),
        const SizedBox(height: 6),
        _PrimaryButton(
          label: widget.working ? 'Saving…' : 'Save changes',
          icon: Icons.save_rounded,
          onTap: widget.working
              ? null
              : () => widget.onSave(BusinessAccount(
                    id: widget.account.id,
                    name: name.text.trim(),
                    status: widget.account.status,
                    contactName: contact.text.trim(),
                    contactEmail: widget.account.contactEmail,
                    phone: phone.text.trim(),
                    billingEmail: billing.text.trim(),
                    businessAddress: address.text.trim(),
                    companyNumber: company.text.trim(),
                    companyCode: widget.account.companyCode,
                    defaultPickupAddress: pickup.text.trim(),
                    teamMembers: widget.account.teamMembers,
                    connectedProducts: widget.account.connectedProducts,
                    notificationPreferences:
                        widget.account.notificationPreferences,
                    paymentPreferences: widget.account.paymentPreferences,
                  )),
        ),
      ]);
}

class _BusinessField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  const _BusinessField(
      {required this.label, required this.controller, this.keyboardType});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: _field,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: _border)),
          ),
        ),
      );
}

class _BusinessLoading extends StatelessWidget {
  const _BusinessLoading();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: _blue));
}

class _BusinessFailure extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _BusinessFailure({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
          child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, color: _muted, size: 40),
          const SizedBox(height: 14),
          const Text('Business could not load.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted)),
          const SizedBox(height: 18),
          FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry')),
        ]),
      ));
}

class _BusinessEmpty extends StatelessWidget {
  final VoidCallback onRetry;
  const _BusinessEmpty({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
          child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.business_outlined, color: _blue, size: 44),
          const SizedBox(height: 14),
          Text('No Business account yet',
              style: GoogleFonts.dmSerifDisplay(fontSize: 25)),
          const SizedBox(height: 8),
          const Text(
              'Create or join a Circum Business account to open this workspace.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted)),
          const SizedBox(height: 18),
          FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Check again')),
        ]),
      ));
}

class _VerificationJourney extends StatelessWidget {
  final String status;
  const _VerificationJourney({required this.status});
  @override
  Widget build(BuildContext context) {
    final rejected = status == 'rejected' || status == 'suspended';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _panel,
          border: Border.all(
              color: rejected
                  ? _danger.withValues(alpha: .45)
                  : _warning.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            rejected ? 'Verification needs attention' : 'Business verification',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          rejected
              ? 'Circum needs more information before this Business account can book deliveries.'
              : 'Your account has been received. Circum will confirm your details before Business booking is enabled.',
          style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.45),
        ),
        const SizedBox(height: 10),
        Row(children: const [
          _JourneyStep(label: 'Submitted', complete: true),
          Expanded(child: Divider(color: _border)),
          _JourneyStep(label: 'Review', complete: false),
          Expanded(child: Divider(color: _border)),
          _JourneyStep(label: 'Verified', complete: false),
        ]),
      ]),
    );
  }
}

class _JourneyStep extends StatelessWidget {
  final String label;
  final bool complete;
  const _JourneyStep({required this.label, required this.complete});
  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(complete ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 18, color: complete ? _success : _mutedDim),
        const SizedBox(height: 3),
        Text(label,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 8.5, color: complete ? _success : _mutedDim)),
      ]);
}

class _Subtitle extends StatelessWidget {
  final String text;
  const _Subtitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(text,
          style: const TextStyle(color: _muted, fontSize: 13, height: 1.5)));
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text.toUpperCase(),
            style: GoogleFonts.jetBrainsMono(
                fontSize: 10.5, letterSpacing: 1.2, color: _mutedDim)),
      );
}

class _ResponsiveGrid extends StatelessWidget {
  final double minItemWidth;
  final double childAspectRatio;
  final List<Widget> children;

  const _ResponsiveGrid({
    required this.minItemWidth,
    required this.childAspectRatio,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns =
          (constraints.maxWidth / minItemWidth).floor().clamp(1, 4).toInt();
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: childAspectRatio,
        children: children,
      );
    });
  }
}

class _CompactKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final VoidCallback? onTap;

  const _CompactKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => _GlassCard(
        onTap: onTap,
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _field,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: _blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: _muted)),
              const SizedBox(height: 3),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? _text,
                  )),
            ]),
          ),
        ]),
      );
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => _GlassCard(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(value, style: GoogleFonts.dmSerifDisplay(fontSize: 22)),
        const SizedBox(height: 5),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, color: _muted)),
      ]));
}

class _MetricChartCard extends StatelessWidget {
  final String title;
  final String value;
  final Map<String, int> bars;

  const _MetricChartCard({
    required this.title,
    required this.value,
    required this.bars,
  });

  @override
  Widget build(BuildContext context) {
    final maxValue =
        bars.values.fold<int>(0, (max, value) => value > max ? value : max);
    final entries = bars.entries.take(5).toList(growable: false);
    return _GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: _muted))),
          Text(value,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        if (entries.isEmpty || maxValue == 0)
          const Text('No data yet.',
              style: TextStyle(color: _mutedDim, fontSize: 12))
        else
          ...entries.map((entry) {
            final fraction = entry.value / maxValue;
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(children: [
                SizedBox(
                  width: 54,
                  child: Text(entry.key,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _mutedDim, fontSize: 10.5)),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 7,
                      backgroundColor: _field,
                      valueColor: const AlwaysStoppedAnimation(_blue),
                    ),
                  ),
                ),
              ]),
            );
          }),
      ]),
    );
  }
}

class _MetricListCard extends StatelessWidget {
  final String title;
  final List<MapEntry<String, int>> items;
  final String empty;

  const _MetricListCard({
    required this.title,
    required this.items,
    required this.empty,
  });

  @override
  Widget build(BuildContext context) => _GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 11.5, color: _muted)),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(empty, style: const TextStyle(color: _mutedDim, fontSize: 12))
          else
            ...items.take(4).map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(children: [
                    Expanded(
                      child: Text(item.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                    Text('${item.value}',
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 12, color: _muted)),
                  ]),
                )),
        ]),
      );
}

class _NotificationSummary extends StatelessWidget {
  final Map<String, dynamic> enabled;
  final int pendingInvoices;
  final int activeDeliveries;

  const _NotificationSummary({
    required this.enabled,
    required this.pendingInvoices,
    required this.activeDeliveries,
  });

  @override
  Widget build(BuildContext context) {
    final muted = enabled.entries
        .where((entry) => entry.value == false)
        .map((entry) => _title(entry.key))
        .toList(growable: false);
    return _GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CompactInfoLine(
            icon: Icons.local_shipping_rounded,
            title: 'Active delivery alerts',
            value: '$activeDeliveries'),
        _CompactInfoLine(
            icon: Icons.receipt_long_rounded,
            title: 'Invoice reminders',
            value: '$pendingInvoices'),
        _CompactInfoLine(
            icon: Icons.notifications_active_rounded,
            title: 'Muted categories',
            value: muted.isEmpty ? 'None' : muted.join(', ')),
      ]),
    );
  }
}

class _CompactInfoLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _CompactInfoLine({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(icon, size: 17, color: _blue),
          const SizedBox(width: 9),
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontSize: 12.5, color: _muted))),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(fontSize: 12)),
          ),
        ]),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _ActionTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap});
  @override
  Widget build(BuildContext context) => _GlassCard(
      onTap: onTap,
      child: Row(children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: _field, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: _mutedDim, height: 1.35)),
              ]),
        ),
      ]));
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _GlassCard({required this.child, this.onTap});
  @override
  Widget build(BuildContext context) => AppGlassContainer(
        padding: const EdgeInsets.all(14),
        radius: AppTokens.radius16,
        surfaceColor: _panel,
        borderColor: _border,
        accent: _blue,
        onTap: onTap,
        child: child,
      );
}

class _OperationalRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? amount;
  final String? status;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _OperationalRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.amount,
      this.status,
      this.trailing,
      this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: _panel,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: _border)),
          child: ListTile(
            onTap: onTap,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
            leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: _field, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18)),
            title: Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
            subtitle: Text(subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5, color: _mutedDim)),
            trailing: trailing ??
                (amount == null && status == null
                    ? null
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                            if (amount != null)
                              Text(amount!,
                                  style: GoogleFonts.jetBrainsMono(
                                      fontSize: 12.5)),
                            if (status != null) ...[
                              const SizedBox(height: 4),
                              _StatusTag(status!)
                            ],
                          ])),
          ),
        ),
      );
}

class _SimpleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SimpleRow(
      {required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) =>
      _OperationalRow(icon: icon, title: title, subtitle: subtitle);
}

class _StatusTag extends StatelessWidget {
  final String label;
  const _StatusTag(this.label);
  @override
  Widget build(BuildContext context) {
    final lower = label.toLowerCase();
    final color = lower.contains('paid') ||
            lower.contains('delivered') ||
            lower.contains('complete')
        ? _success
        : lower.contains('due') || lower.contains('pending')
            ? _warning
            : _blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(100)),
      child: Text(label.toUpperCase(),
          style: GoogleFonts.jetBrainsMono(
              fontSize: 8.5, color: color, letterSpacing: .3)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _EmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Icon(icon, color: _mutedDim, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: _mutedDim, fontSize: 12.5, height: 1.45)),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 10),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      );
}

class _InformationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool accented;
  const _InformationCard(
      {required this.icon,
      required this.title,
      required this.body,
      this.accented = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          gradient: accented
              ? LinearGradient(colors: [
                  _blue.withValues(alpha: .12),
                  _blue.withValues(alpha: .02)
                ])
              : null,
          color: accented ? null : _panel,
          border: Border.all(
              color: accented ? _blue.withValues(alpha: .3) : _border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: accented ? _blue : _muted),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: GoogleFonts.dmSerifDisplay(fontSize: 17)),
                const SizedBox(height: 5),
                Text(body,
                    style: const TextStyle(
                        color: _muted, fontSize: 12, height: 1.5)),
              ])),
        ]),
      );
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField(
      {required this.controller, required this.hint, required this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: hint,
            filled: true,
            fillColor: _field,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
                borderSide: const BorderSide(color: _border))),
      );
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _PrimaryButton({required this.label, required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) =>
      AppButton(label: label, icon: icon, onPressed: onTap);
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _SecondaryButton({required this.label, required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) => AppButton(
      label: label,
      icon: icon,
      onPressed: onTap,
      style: AppButtonStyle.secondary,
      expanded: false);
}

class _CompactAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _CompactAction(
      {required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(side: const BorderSide(color: _border)));
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 170),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: _raised,
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(100)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)))
        ]),
      );
}

class _StatusPill extends StatelessWidget {
  final bool approved;
  final String label;
  const _StatusPill({required this.approved, required this.label});
  @override
  Widget build(BuildContext context) {
    final color = approved ? _success : _warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          border: Border.all(color: color.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(100)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(approved ? '$label ✓' : label,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 10.5, color: color, letterSpacing: .4))
      ]),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;
  const _DetailLine({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(label, style: const TextStyle(color: _muted))),
        const SizedBox(width: 16),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700)))
      ]));
}

IconData _paymentIcon(SenderPaymentProfileOptionType type) => switch (type) {
      SenderPaymentProfileOptionType.applePay => Icons.apple_rounded,
      SenderPaymentProfileOptionType.googlePay =>
        Icons.account_balance_wallet_rounded,
      SenderPaymentProfileOptionType.savedCard => Icons.credit_card_rounded,
      SenderPaymentProfileOptionType.addPaymentMethod => Icons.add_card_rounded,
    };

String _paymentMethodValue(SenderPaymentProfileOption? option) =>
    switch (option?.type) {
      SenderPaymentProfileOptionType.applePay => 'apple_pay',
      SenderPaymentProfileOptionType.googlePay => 'google_pay',
      SenderPaymentProfileOptionType.savedCard => 'saved_card',
      _ => 'card',
    };

bool _isOverdue(BusinessInvoice invoice) {
  final due = invoice.dueAt;
  return !invoice.isPaid && due != null && due.isBefore(DateTime.now());
}

Map<String, int> _amountBars(List<BusinessDelivery> deliveries) {
  final values = <String, int>{};
  for (final item in deliveries) {
    final date = item.createdAt ?? item.scheduledAt;
    if (date == null) continue;
    final key = DateFormat('MMM').format(date);
    values[key] = (values[key] ?? 0) + item.amount.round();
  }
  return values;
}

List<MapEntry<String, int>> _topEntries(Map<String, int> values) {
  final entries = values.entries
      .where((entry) => entry.key.trim().isNotEmpty)
      .toList(growable: false);
  entries.sort((a, b) => b.value.compareTo(a.value));
  return entries;
}

String _gbp(double value) =>
    NumberFormat.currency(locale: 'en_GB', symbol: '£').format(value);
String _title(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
String _statusLabel(String value) => _title(
    value == 'requested' || value == 'broadcasting' ? 'in_progress' : value);
String _dayPart() {
  final hour = DateTime.now().hour;
  return hour < 12
      ? 'morning'
      : hour < 18
          ? 'afternoon'
          : 'evening';
}

String _shortBusinessName(String name) => name
    .replaceAll(RegExp(r'\s+(Ltd|Limited|PLC|LLP)$', caseSensitive: false), '')
    .trim();
