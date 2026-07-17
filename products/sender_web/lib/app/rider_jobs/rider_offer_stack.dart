import 'package:flutter/material.dart';

import 'rider_job_models.dart';
import 'rider_offer_card.dart';

class RiderOfferStack extends StatefulWidget {
  final List<RiderJobOffer> offers;
  final ValueChanged<RiderJobOffer> onAccept;
  final bool accepting;

  const RiderOfferStack({
    super.key,
    required this.offers,
    required this.onAccept,
    this.accepting = false,
  });

  @override
  State<RiderOfferStack> createState() => _RiderOfferStackState();
}

class _RiderOfferStackState extends State<RiderOfferStack> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.offers.isEmpty) {
      return const Center(
        child: Text(
          'No eligible offers right now.',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
        ),
      );
    }
    final active = widget.offers[_index.clamp(0, widget.offers.length - 1)];
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Pill(label: '${widget.offers.length} Available Offers'),
            _Pill(label: '${_index + 1} of ${widget.offers.length}'),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Swipe to view more',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .56),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -120 && _index < widget.offers.length - 1) {
              setState(() => _index += 1);
            } else if (velocity > 120 && _index > 0) {
              setState(() => _index -= 1);
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_index + 1 < widget.offers.length)
                Transform.translate(
                  offset: const Offset(18, 18),
                  child: Opacity(
                    opacity: .28,
                    child: RiderOfferCard(
                      offer: widget.offers[_index + 1],
                      onAccept: null,
                    ),
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: RiderOfferCard(
                  key: ValueKey(active.id),
                  offer: active,
                  accepting: widget.accepting,
                  onAccept: () => widget.onAccept(active),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;

  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
