import 'package:flutter/material.dart';

/// Shared Roth presentation primitives. These widgets contain no financial
/// policy; callers remain responsible for balances and payment decisions.
class RothChoiceCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String description;
  final VoidCallback onTap;

  const RothChoiceCard({
    super.key,
    required this.selected,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = selected ? const Color(0xFFD9BE63) : const Color(0xFF9FA8BC);
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $description',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: selected ? .10 : .055),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: accent.withValues(alpha: selected ? .55 : .18)),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.account_balance_wallet_outlined,
                color: accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(description,
                        style: const TextStyle(
                            color: Color(0xFFB9C1D2), height: 1.35)),
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

class RothApplyCard extends StatelessWidget {
  final bool enabled;
  final double balance;
  final double applied;
  final double remaining;
  final ValueChanged<bool> onChanged;

  const RothApplyCard({
    super.key,
    required this.enabled,
    required this.balance,
    required this.applied,
    required this.remaining,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            onChanged: onChanged,
            title: const Text('Apply Roth balance',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          if (enabled) ...[
            const SizedBox(height: 4),
            _RothValueRow(label: 'Roth balance', value: balance),
            _RothValueRow(label: 'Roth applied', value: applied),
            _RothValueRow(label: 'Remaining card amount', value: remaining),
          ],
        ],
      ),
    );
  }
}

class RothSummaryCard extends StatelessWidget {
  final bool loading;
  final bool unavailable;
  final double balance;
  final double applied;
  final double remaining;

  const RothSummaryCard({
    super.key,
    required this.loading,
    required this.unavailable,
    required this.balance,
    required this.applied,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    final balanceText = loading
        ? 'Loading...'
        : unavailable
            ? 'Unavailable'
            : _money(balance);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Column(
        children: [
          _RothTextRow(label: 'Available Roth balance', value: balanceText),
          _RothTextRow(label: 'Amount covered by Roth', value: _money(applied)),
          _RothTextRow(
              label: 'Remaining card amount', value: _money(remaining)),
          if (unavailable) ...[
            const SizedBox(height: 10),
            const Text(
              'Roth is currently unavailable. You can continue securely by card.',
              style: TextStyle(color: Color(0xFFB9C1D2), height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _RothValueRow extends StatelessWidget {
  final String label;
  final double value;

  const _RothValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => _RothTextRow(
        label: label,
        value: _money(value),
      );
}

class _RothTextRow extends StatelessWidget {
  final String label;
  final String value;

  const _RothTextRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child:
                  Text(label, style: const TextStyle(color: Color(0xFFB9C1D2))),
            ),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

String _money(double value) => '£${value.toStringAsFixed(2)}';
