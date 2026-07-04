import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'rider_job_models.dart';
import 'rider_points_rules.dart';

class RiderOfferCard extends StatelessWidget {
  final RiderJobOffer offer;
  final VoidCallback? onAccept;
  final bool accepting;

  const RiderOfferCard({
    super.key,
    required this.offer,
    required this.onAccept,
    this.accepting = false,
  });

  @override
  Widget build(BuildContext context) {
    final award = RiderPointsRules.awardFor(offer.categories);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .075),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: .16)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6).withValues(alpha: .18),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '£${offer.estimatedEarnings.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Estimated earnings',
                          style: _mutedStyle(),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _Badge(
                          label: offer.riderRank,
                          color: const Color(0xFF60A5FA)),
                      const SizedBox(height: 8),
                      _Badge(
                        label: '+${award.points} Trust',
                        color: const Color(0xFF18BC5A),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Badge(label: award.label, color: const Color(0xFF3B82F6)),
                  ...offer.warningChips.map(
                    (chip) =>
                        _Badge(label: chip, color: const Color(0xFF38BDF8)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${offer.pickupArea} → ${offer.dropoffArea}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Meta(label: offer.distanceLabel, icon: Icons.route_outlined),
                  const SizedBox(width: 10),
                  _Meta(label: offer.etaLabel, icon: Icons.schedule_rounded),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'IRIS: ${offer.parcelSummary}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE5ECFF),
                  height: 1.3,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${offer.vehicleLabel} • ${offer.weightLabel} • ${offer.pickupTimingLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white.withValues(alpha: .64),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: accepting ? null : onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: Text(accepting ? 'Accepting…' : 'Accept Delivery'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _mutedStyle() {
    return TextStyle(
      color: Colors.white.withValues(alpha: .58),
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .34)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Meta({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 15, color: const Color(0xFF60A5FA)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
