import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../utils/theme/theme.dart';
import '../bloc/send_package_bloc.dart';

class RatingsView extends StatefulWidget {
  RatingsView({Key? key}) : super(key: key);

  @override
  State<RatingsView> createState() => _RatingsViewState();
}

class _RatingsViewState extends State<RatingsView> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: ((context, state) {
      return Scaffold(
        backgroundColor: AppColors.secondary,
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppText.text("Rate Courier’s Service",
                    fontSize: 18, fontWeight: FontWeight.w600),
              ],
            ),
            const SizedBox(height: 24),
            RatingBar(
              initialRating: 0,
              itemSize: 48,
              direction: Axis.horizontal,
              allowHalfRating: true,
              itemCount: 5,
              ratingWidget: RatingWidget(
                full: SvgPicture.asset('assets/svg/star_full.svg'),
                half: SvgPicture.asset('assets/svg/star_half.svg'),
                empty: SvgPicture.asset('assets/svg/star_empty.svg'),
              ),
              itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
              onRatingUpdate: (rating) {
                Navigator.pop(context);
                // print(rating);
              },
            ),
          ],
        ),
      );
    }));
  }
}
