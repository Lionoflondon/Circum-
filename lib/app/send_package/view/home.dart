import 'dart:async';

import 'package:circum/app/authentication/bloc/auth_bloc.dart';
import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/helper/google_map_controller.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:shimmer/shimmer.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

// import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../utils/theme/theme.dart';
import '../../send_package/view/delivery_review_expanded.dart';
import '../../send_package/view/index.dart';
import 'parts/active_delivery_details.dart';
import 'parts/connecting_with_rider.dart';
import 'parts/initial_bs.dart';
import 'ratings.dart';

part './parts/delivery_review.dart';
part './parts/connecting.dart';

class HomeView extends StatefulWidget {
  const HomeView({Key? key}) : super(key: key);
  @override
  HomeViewState createState() => HomeViewState();
}

class HomeViewState extends State<HomeView> {
  PanelController panelController = PanelController();
  @override
  void initState() {
    context.read<SendPackageBloc>().add(CheckForPushToken());
    context.read<SendPackageBloc>().add(CheckForActiveRequest());
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (state.deliveryStatus == DeliveryStatus.deliveryCompleted) {
          context.read<SendPackageBloc>().add(
              const SetDeliveryStatus(deliveryStatus: DeliveryStatus.inital));
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => RatingsView()));
        }
      });
      if (state.panelControlStatus == PanelControlStatus.isOpened) {
        panelController.animatePanelToPosition(1);
        context
            .read<SendPackageBloc>()
            .add(SetPanelControlStatus(status: PanelControlStatus.initialized));
      }
      return SlidingUpPanel(
          color: Colors.red,
          controller: panelController,
          minHeight: state.minDrawerHeight,
          maxHeight: state.maxDrawerHeight,
          onPanelOpened: () {
            context.read<SendPackageBloc>().add(
                SetPanelControlStatus(status: PanelControlStatus.isOpened));
          },
          onPanelClosed: () {
            context.read<SendPackageBloc>().add(
                SetPanelControlStatus(status: PanelControlStatus.isClosed));
          },
          panel: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              color: AppColors.secondary,
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 5,
                      width: 50,
                      margin: const EdgeInsets.only(top: 10, bottom: 20),
                      decoration: BoxDecoration(
                          color: const Color(0xFF415058),
                          borderRadius: BorderRadius.circular(5)),
                    ),
                  ],
                ),
                Expanded(
                    child: SingleChildScrollView(
                        physics: state.panelControlStatus ==
                                PanelControlStatus.isClosed
                            ? NeverScrollableScrollPhysics()
                            : BouncingScrollPhysics(),
                        child: Column(children: [
                          if (state.deliveryStatus == DeliveryStatus.inital)
                            const InitialBS(),
                          if (state.deliveryStatus ==
                              DeliveryStatus.reconnectingWithRider)
                            const ConnectingWithARider(),
                          if (state.deliveryStatus ==
                              DeliveryStatus.addressesSelected)
                            deliveryReview(),
                          if (state.deliveryStatus ==
                              DeliveryStatus.deliveryConfirmed)
                            const ConnectingToCourier(),
                          if (state.deliveryStatus ==
                                  DeliveryStatus.deliveryOnGoing &&
                              state.deliveryData != null)
                            const ActiveDeliveryDetails()
                        ])))
              ])));
    });
  }
}
