import 'dart:async';

import 'package:circum/app/authentication/bloc/auth_bloc.dart';
import 'package:circum/app/home/bloc/home_bloc.dart';
import 'package:circum/helper/google_map_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_maps_widget/google_maps_widget.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../utils/theme/theme.dart';
import '../../send_package/view/index.dart';

class HomeView extends StatefulWidget {
  const HomeView({Key? key}) : super(key: key);

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  Widget build(BuildContext context) {
    return Container(
        color: AppColors.secondary,
        child: Column(
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
        ));
  }

  Widget whereToButton() {
    return BlocBuilder<HomeBloc, HomeState>(builder: (context, state) {
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
          onPressed: () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChooseAddressView()));
          });
    });
  }

  Widget onGoingRequests() {
    return BlocBuilder<HomeBloc, HomeState>(builder: (context, state) {
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
