import 'dart:async';

import 'package:circum/app/authentication/bloc/auth_bloc.dart';
import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/helper/google_map_controller.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';

// import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../utils/theme/theme.dart';
import '../../send_package/view/delivery_review_expanded.dart';
import '../../send_package/view/index.dart';

part './parts/delivery_review.dart';
part './parts/connecting.dart';

class HomeView extends StatefulWidget {
  const HomeView({Key? key}) : super(key: key);
  @override
  HomeViewState createState() => HomeViewState();
}

class HomeViewState extends State<HomeView> {
  @override
  void initState() {
    context.read<SendPackageBloc>().add(CheckForPushToken());
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      return AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          color: AppColors.secondary,
          child: Column(children: [
            if (state.deliveryStatus == DeliveryStatus.inital)
              Column(
                children: [
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.only(left: 24, right: 24),
                    child: whereToButton(),
                  ),
                  const SizedBox(height: 36),
                  onGoingRequests(),
                  const SizedBox(height: 24),
                ],
              ),
            if (state.deliveryStatus == DeliveryStatus.addressesSelected)
              deliveryReview(),
            if (state.deliveryStatus == DeliveryStatus.deliveryConfirmed)
              const ConnectingToCourier(),
          ]));
    });
  }

  Widget whereToButton() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      return AppButton.button(
          backgroundColor: AppColors.input,
          widget: Row(
            children: [
              const SizedBox(width: 5),
              SvgPicture.asset('assets/svg/search.svg'),
              const SizedBox(width: 16),
              AppText.text('Where to?', color: Colors.white.withOpacity(0.3))
            ],
          ),
          onPressed: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChooseAddressView()));
            // setState(() {});
          });
    });
  }

  Widget onGoingRequests() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      if (state.ongoingRequests.length > 0) {
        return SizedBox(
            width: double.maxFinite,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: AppText.text('Ongoing Requests',
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (contxt, index) {
                      return TextButton(
                          // borderSide: BorderSide.none,
                          // backgroundColor: AppColors.secondary,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 5),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                children: [
                                  AppText.text('Placeholder Address',
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600),
                                  AppText.text('Placeholder subaddress',
                                      color: AppColors.textGrey)
                                ],
                              ),
                              Icon(
                                Icons.keyboard_arrow_right_rounded,
                                color: Colors.white.withOpacity(0.15),
                              )
                            ],
                          ),
                          onPressed: () {});
                    },
                    separatorBuilder: (_, i) => Divider(
                        height: 5,
                        thickness: 1,
                        color: Colors.white.withOpacity(0.15)),
                    itemCount: state.ongoingRequests.length)
              ],
            ));
      }
      return Container();
    });
  }
}
