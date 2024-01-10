import 'package:currency_symbols/currency_symbols.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../helper/format_date.dart';
import '../../../utils/theme/theme.dart';
import '../../send_package/models/dispatch_request.m..dart';

class HistoryDetailsView extends StatefulWidget {
  final DispatchRequest data;
  const HistoryDetailsView({Key? key, required this.data}) : super(key: key);

  @override
  State<HistoryDetailsView> createState() => _HistoryDetailsViewState();
}

class _HistoryDetailsViewState extends State<HistoryDetailsView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        foregroundColor: Colors.white,
        backgroundColor: AppColors.secondary,
        centerTitle: true,
        elevation: 1,
        title: AppText.text('${widget.data.dropoffData.address}',
            fontSize: 16, fontWeight: FontWeight.bold),
      ),
      backgroundColor: AppColors.secondary,
      body: SafeArea(
          child: SingleChildScrollView(
              child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(
            color: AppColors.borderColor,
            thickness: 1,
            height: 1,
          ),
          Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.text('${widget.data.dropoffData.address}',
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600),
                  Row(
                    children: [
                      AppText.text(
                          '${cSymbol(widget.data.currency)}${widget.data.price}',
                          color: AppColors.textGrey),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.circle,
                        color: AppColors.textGrey,
                        size: 6,
                      ),
                      const SizedBox(width: 8),
                      AppText.text(formatTimestamp(widget.data.createdAt!),
                          fontSize: 12, color: AppColors.textGrey)
                    ],
                  ),
                ],
              )),
          const Divider(
            color: AppColors.borderColor,
            thickness: 1,
            height: 1,
          ),
          Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.text('Delivery Details',
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                  const SizedBox(height: 20),
                  AppText.text('Contact Name',
                      fontSize: 12, color: AppColors.textGrey),
                  const SizedBox(height: 8),
                  AppText.text('${widget.data.pickupData.fullname}',
                      color: Colors.white, fontSize: 16),
                  const SizedBox(height: 12),
                  const Divider(
                    color: AppColors.borderColor,
                    thickness: 1,
                    height: 1,
                  ),
                  const SizedBox(height: 12),
                  AppText.text('Contact Number',
                      fontSize: 12, color: AppColors.textGrey),
                  const SizedBox(height: 8),
                  AppText.text('${widget.data.pickupData.phoneNumber}',
                      color: Colors.white, fontSize: 16),
                  if (widget.data.pickupData.moreInformation != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        const Divider(
                          color: AppColors.borderColor,
                          thickness: 1,
                          height: 1,
                        ),
                        const SizedBox(height: 12),
                        AppText.text('More Information',
                            fontSize: 12, color: AppColors.textGrey),
                        const SizedBox(height: 8),
                        AppText.text(
                            '${widget.data.pickupData.moreInformation}',
                            color: Colors.white,
                            fontSize: 16),
                      ],
                    )
                ],
              )),
          const Divider(
            color: AppColors.borderColor,
            thickness: 1,
            height: 1,
          ),
          Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.text('Rider Rating',
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SvgPicture.asset(
                        'assets/svg/account.svg',
                        height: 32,
                      ),
                      const SizedBox(width: 14),
                      AppText.text(widget.data.riderName ?? ''),
                      const Spacer(),
                      if (widget.data.userRating != null)
                        RatingBar(
                          initialRating: widget.data.userRating!,
                          itemSize: 16,
                          direction: Axis.horizontal,
                          allowHalfRating: true,
                          ignoreGestures: true,
                          itemCount: 5,
                          ratingWidget: RatingWidget(
                            full: SvgPicture.asset('assets/svg/star_full.svg'),
                            half: SvgPicture.asset('assets/svg/star_half.svg'),
                            empty:
                                SvgPicture.asset('assets/svg/star_empty.svg'),
                          ),
                          itemPadding:
                              const EdgeInsets.symmetric(horizontal: 4.0),
                          onRatingUpdate: (rating) {
                            // Navigator.pop(context);
                            // print(rating);
                          },
                        ),
                    ],
                  ),
                ],
              )),
          const Divider(
            color: AppColors.borderColor,
            thickness: 1,
            height: 1,
          ),
        ],
      ))),
    );
  }
}
