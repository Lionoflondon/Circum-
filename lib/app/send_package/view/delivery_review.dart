import 'dart:async';

import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/utils/theme/theme.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'delivery_review_expanded.dart';

class DeliveryReviewView extends StatefulWidget {
  DeliveryReviewView({Key? key}) : super(key: key);

  @override
  State<DeliveryReviewView> createState() => _DeliveryReviewViewState();
}

class _DeliveryReviewViewState extends State<DeliveryReviewView> {
  // final Completer<GoogleMapController> _controller =
  //     Completer<GoogleMapController>();

  // static const CameraPosition _kGooglePlex = CameraPosition(
  //   target: LatLng(55.838175, -4.272892),
  //   zoom: 14.4746,
  // );

  // static const CameraPosition _kLake = CameraPosition(
  //     bearing: 192.8334901395799,
  //     target: LatLng(37.43296265331129, -122.08832357078792),
  //     tilt: 59.440717697143555,
  //     zoom: 19.151926040649414);

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.secondary,
        body: SafeArea(
            child: Stack(
          children: [
            Column(
              children: [
                // Expanded(
                //     child: GoogleMap(
                //   mapType: MapType.normal,
                //   initialCameraPosition: _kLake,
                //   onMapCreated: (GoogleMapController controller) {
                //     _controller.complete(controller);
                //   },
                // )),
                Container(
                  color: AppColors.secondary,
                  child: Column(
                    children: [
                      const SizedBox(height: 44),
                      selectedAddresses(),
                      const SizedBox(height: 38),
                      deliveryCost(),
                      const SizedBox(height: 66),
                      reviewButton(),
                      const SizedBox(height: 32),
                    ],
                  ),
                )
              ],
            ),
            Padding(
              padding: EdgeInsets.only(),
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: Color(0xFF1F292E),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            )
          ],
        )));
  }

  Widget selectedAddresses() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              const SizedBox(
                  height: 85,
                  child: Column(
                    children: [
                      Icon(
                        Icons.circle,
                        color: Color(0xFF2D89D4),
                        size: 10,
                      ),
                      Expanded(
                          child: DottedLine(
                        direction: Axis.vertical,
                        dashColor: Color(0xFF1F292E),
                      )),
                      Icon(
                        Icons.circle,
                        size: 10,
                        color: Color(0xFF65C436),
                      ),
                    ],
                  )),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.text(state.pickupLocation!,
                      fontSize: 16, fontWeight: FontWeight.w600),
                  AppText.text(state.pickupLocationSubAddress!,
                      fontSize: 12, color: const Color(0xFFC9D2D7)),
                  const SizedBox(height: 12),
                  AppText.text(state.destinationLocation!,
                      fontSize: 16, fontWeight: FontWeight.w600),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      AppText.text(state.destinationLocationSubAddress!,
                          fontSize: 12, color: const Color(0xFFC9D2D7)),
                      AppText.text('${state.distance}km away',
                          fontSize: 12, color: const Color(0xFFC9D2D7)),
                    ],
                  )
                ],
              )),
            ],
          ));
    });
  }

  Widget deliveryCost() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: ((context, state) {
      return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: const BoxDecoration(color: Color(0xFF415058)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AppText.text('\$20',
                      fontSize: 24, fontWeight: FontWeight.w600),
                  AppText.text('Delivery price',
                      fontSize: 12, color: const Color(0xFFC9D2D7)),
                ],
              )
            ],
          ));
    }));
  }

  Widget reviewButton() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: AppButton.button(
          widget: Center(
              child: AppText.text('Review delivery',
                  fontSize: 16, fontWeight: FontWeight.bold)),
          onPressed: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => DeliveryReviewExpandedView()));
          }),
    );
  }
}
