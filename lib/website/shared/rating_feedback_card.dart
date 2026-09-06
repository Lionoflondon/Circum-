import 'package:flutter/material.dart';
import 'policies/driver_performance.dart';

class RiderWebRatingFeedback extends StatelessWidget {
  final Color background;
  final Color mutedText;
  final VoidCallback onReport;
  final DriverRating rating;

  const RiderWebRatingFeedback(
      {super.key,
      required this.background,
      required this.mutedText,
      required this.onReport,
      required this.rating});

  @override
  Widget build(BuildContext context) {
    final feedback = rating.hiddenByAdmin
        ? 'Written feedback hidden by Circum.'
        : rating.feedbackText.trim().isNotEmpty
            ? rating.feedbackText.trim()
            : rating.feedbackTags.isNotEmpty
                ? rating.feedbackTags.join(', ')
                : 'No written feedback';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                label: '${rating.starRating} out of 5 stars',
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (index) => Icon(
                          index < rating.starRating
                              ? Icons.star
                              : Icons.star_border,
                          size: 20,
                          color: const Color(0xffffb020)),
                    )),
              ),
              const Spacer(),
              Flexible(
                  child: Text(
                rating.deliveryCategories.isEmpty
                    ? 'Delivery'
                    : rating.deliveryCategories.join(' + '),
                style: TextStyle(
                  color: mutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              )),
            ],
          ),
          if (rating.createdAt != null)
            Text(
                '${rating.createdAt!.day}/${rating.createdAt!.month}/${rating.createdAt!.year}',
                style: TextStyle(color: mutedText, fontSize: 12)),
          TextButton(
            onPressed: onReport,
            child: const Text('Report feedback'),
          ),
          const SizedBox(height: 8),
          Text(
            feedback,
            style: TextStyle(
              color: mutedText,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
