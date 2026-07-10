import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../health_plus/view/health_plus.dart';
import '../sender_mobile/gift_mode_view.dart';
import '../sender_mobile/sender_booking_canvas.dart';
import '../sender_mobile/sender_finance.dart';
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
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseBusinessRepository();
    _paymentRepository = widget.paymentProfileRepository ??
        FirebaseSenderPaymentProfileRepository();
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
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _account = selected;
        _workspace = results[0] as BusinessWorkspaceData;
        _paymentProfile = results[1] as SenderPaymentProfile;
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
    final theme = ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: _navy,
      colorScheme: const ColorScheme.dark(primary: _blue, surface: _panel),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
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
        _StatusPill(approved: account.isApproved, label: account.statusLabel),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle(
          'Your command centre for deliveries, invoices, team access, Health+, Gifts, Vanguard and operational insights.'),
      const _SectionLabel('This month'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.28,
        children: [
          _StatCard(
              label: 'Monthly Deliveries',
              value: '${data.monthlyDeliveries}',
              onTap: () => _selectSection(BusinessSection.deliveries)),
          _StatCard(
              label: 'Outstanding Balance',
              value: _gbp(data.outstandingBalance),
              onTap: () => _selectSection(BusinessSection.finance)),
          _StatCard(
              label: 'Team Members',
              value: '${data.account.teamMembers.length}',
              onTap: () => _selectSection(BusinessSection.team)),
          _StatCard(
              label: 'Roth Offset',
              value: _gbp(data.wallet.lifetimeOffset),
              valueColor: _roth,
              onTap: () => _selectSection(BusinessSection.finance)),
        ],
      ),
      const _SectionLabel('Quick actions'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.06,
        children: [
          _ActionTile(
              icon: Icons.local_shipping_rounded,
              title: 'Book a delivery',
              subtitle: 'Use your approved Business account',
              onTap: _bookDelivery),
          _ActionTile(
              icon: Icons.person_add_alt_1_rounded,
              title: 'Invite teammate',
              subtitle: 'Add booking or admin access',
              onTap: _inviteMember),
          _ActionTile(
              icon: Icons.health_and_safety_rounded,
              title: 'Health+ request',
              subtitle: 'Open your connected Health+ service',
              onTap: _openHealthPlus),
          _ActionTile(
              icon: Icons.card_giftcard_rounded,
              title: 'Corporate gift',
              subtitle: 'Create a confidential gift request',
              onTap: _openGifts),
        ],
      ),
      const _SectionLabel('Recent activity'),
      if (data.deliveries.isEmpty && data.invoices.isEmpty)
        const _EmptyState(
            icon: Icons.history_rounded,
            message:
                'Business activity will appear here as your team begins using Circum.')
      else ...[
        ...data.deliveries.take(3).map(_deliveryRow),
        ...data.invoices
            .take(math.max(0, 3 - data.deliveries.length))
            .map(_invoiceRow),
      ],
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
        const _EmptyState(
            icon: Icons.local_shipping_outlined,
            message: 'No deliveries in this view.')
      else
        ...filtered.map(_deliveryRow),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: _SecondaryButton(
                label: 'Export',
                icon: Icons.download_rounded,
                onTap: () =>
                    _showMessage('Delivery export is being prepared.'))),
        const SizedBox(width: 8),
        Expanded(
            child: _SecondaryButton(
                label: 'Filter',
                icon: Icons.filter_list_rounded,
                onTap: () => _showMessage(
                    'Use the status tabs and search to filter deliveries.'))),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle(
          'View invoice history, delivery breakdowns, statements and Roth offsets.'),
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
            label: 'Statement History',
            icon: Icons.history_rounded,
            onTap: () => _showMessage(
                'Statement history uses your existing invoice records.')),
        _CompactAction(
            label: 'Download CSV',
            icon: Icons.table_view_rounded,
            onTap: () => _showMessage('Invoice CSV export is being prepared.')),
        _CompactAction(
            label: 'VAT Invoice',
            icon: Icons.description_rounded,
            onTap: () =>
                _showMessage('Open an invoice to view its VAT record.')),
      ]),
    ]);
  }

  Widget _team() {
    final members = _workspace!.account.teamMembers;
    final active =
        members.where((item) => item['status'] != 'invited').toList();
    final pending =
        members.where((item) => item['status'] == 'invited').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle('Invite, suspend and permission team members by role.'),
      _PrimaryButton(
          label: 'Invite teammate',
          icon: Icons.person_add_alt_1_rounded,
          onTap: _inviteMember),
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
    ]);
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
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8,
        childAspectRatio: .9,
        children: [
          _MiniStat(label: 'Active Requests', value: '$active'),
          _MiniStat(
              label: isHealth ? 'Scheduled Pickups' : 'Awaiting Approval',
              value: '${requests.where((item) => const {
                    'scheduled',
                    'pending_approval'
                  }.contains(item.status)).length}'),
          _MiniStat(label: 'Completed', value: '$completed'),
        ],
      ),
      const SizedBox(height: 14),
      if (requests.isEmpty)
        _EmptyState(
            icon: isHealth
                ? Icons.health_and_safety_outlined
                : Icons.card_giftcard_outlined,
            message: 'No $title requests yet.')
      else
        ...requests
            .take(10)
            .map((item) => _requestRow(item, isHealth: isHealth)),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle('Review sensitive deliveries and Vanguard-covered jobs.'),
      const _InformationCard(
        icon: Icons.shield_rounded,
        title: 'Vanguard assurance',
        body:
            'Higher-trust riders, stronger verification and a full audit trail for jobs that need careful handling. Vanguard is delivery assurance, not insurance.',
        accented: true,
      ),
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
    final averageCost = completed.isEmpty
        ? 0.0
        : completed.fold<double>(0, (sum, item) => sum + item.amount) /
            completed.length;
    final timed = completed.where((item) => item.duration != null).toList();
    final averageMinutes = timed.isEmpty
        ? 0
        : timed.fold<int>(0, (sum, item) => sum + item.duration!.inMinutes) ~/
            timed.length;
    final categories = <String, int>{};
    final locations = <String, int>{};
    for (final item in _workspace!.deliveries) {
      categories[item.category] = (categories[item.category] ?? 0) + 1;
      if (item.dropoff.isNotEmpty) {
        locations[item.dropoff] = (locations[item.dropoff] ?? 0) + 1;
      }
    }
    String topKey(Map<String, int> values) => values.entries.isEmpty
        ? 'Not available'
        : (values.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    final monthlySpend = _workspace!.deliveries.where((item) {
      final date = item.createdAt;
      final now = DateTime.now();
      return date != null && date.year == now.year && date.month == now.month;
    }).fold<double>(0, (sum, item) => sum + item.amount);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle(
          'Clear operational answers drawn from your delivery history.'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.2,
        children: [
          _StatCard(label: 'Average Delivery Cost', value: _gbp(averageCost)),
          _StatCard(
              label: 'Average Delivery Time',
              value: averageMinutes == 0
                  ? 'Not available'
                  : '$averageMinutes min'),
          _StatCard(
              label: 'Completed Deliveries', value: '${completed.length}'),
          _StatCard(label: 'Monthly Spend', value: _gbp(monthlySpend)),
          _StatCard(
              label: 'Repeat Locations',
              value: topKey(locations),
              compact: true),
          _StatCard(
              label: 'Top Spend Category',
              value: topKey(categories),
              compact: true),
        ],
      ),
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
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.2,
        children: [
          _StatCard(
              label: 'Outstanding Balance',
              value: _gbp(_workspace!.outstandingBalance)),
          _StatCard(
              label: 'Roth Offset',
              value: _gbp(_workspace!.wallet.lifetimeOffset),
              valueColor: _roth),
          _StatCard(label: 'Invoices', value: '${_workspace!.invoices.length}'),
          _StatCard(
              label: 'Available Roth',
              value: _workspace!.wallet.rothBalance.toStringAsFixed(2),
              valueColor: _roth),
        ],
      ),
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
      const _SectionLabel('Invoices & statements'),
      ..._workspace!.invoices.take(4).map(_invoiceRow),
      if (_workspace!.invoices.isEmpty)
        const _EmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'No invoice or statement history yet.'),
    ]);
  }

  Widget _settings() {
    final account = _account!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Subtitle(
          'Manage your Business details, billing, preferences and connected products.'),
      _SettingsForm(account: account, working: _working, onSave: _saveSettings),
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
      const _SectionLabel('Notifications'),
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
          PopupMenuItem(value: 'suspend', child: Text('Suspend')),
          PopupMenuItem(value: 'remove', child: Text('Remove')),
        ],
      ),
    );
  }

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
    var role = 'operations';
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
              items: const ['operations', 'admin', 'billing', 'member']
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

  Future<void> _handleMemberAction(
      Map<String, dynamic> member, String action) async {
    if (action == 'role') {
      final role = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          backgroundColor: _raised,
          title: const Text('Change role'),
          children: const ['operations', 'admin', 'billing', 'member']
              .map((item) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, item),
                  child: Text(_title(item))))
              .toList(growable: false),
        ),
      );
      if (role == null) return;
      await _repository.updateMember(
          account: _account!, member: member, role: role);
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

  Future<void> _showInvoiceDetails(BusinessInvoice invoice) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _raised,
      showDragHandle: true,
      builder: (context) => Padding(
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
                      await _payInvoice(invoice);
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

  Future<void> _payInvoice(BusinessInvoice invoice) async {
    try {
      setState(() => _working = true);
      final uri = await _repository.createInvoiceCheckout(
          account: _account!, invoice: invoice);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final bool compact;
  const _StatCard(
      {required this.label,
      required this.value,
      this.valueColor,
      this.onTap,
      this.compact = false});
  @override
  Widget build(BuildContext context) => _GlassCard(
        onTap: onTap,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11.5, color: _muted)),
              const SizedBox(height: 8),
              Text(value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: compact
                      ? const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)
                      : GoogleFonts.dmSerifDisplay(
                          fontSize: 22, color: valueColor ?? _text)),
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
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: _field, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18)),
            const SizedBox(height: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, color: _mutedDim, height: 1.35)),
          ]));
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _GlassCard({required this.child, this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: _panel,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _border)),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(padding: const EdgeInsets.all(14), child: child)),
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
  const _EmptyState({required this.icon, required this.message});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Icon(icon, color: _mutedDim, size: 28),
          const SizedBox(height: 9),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _mutedDim, fontSize: 12.5, height: 1.5))
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
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)))));
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _SecondaryButton({required this.label, required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          side: const BorderSide(color: _border),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
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
