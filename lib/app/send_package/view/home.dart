import 'dart:async';

import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

// import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../utils/theme/theme.dart';
import '../../send_package/view/delivery_review_expanded.dart';
import 'parts/active_delivery_details.dart';
import 'parts/connecting_with_rider.dart';
import 'parts/initial_bs.dart';
import 'ratings.dart';

part './parts/delivery_review.dart';
part './parts/connecting.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});
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
          context.read<SendPackageBloc>().add(DeleteCompletedDelivery());

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
          color: const Color(0xFF07090F),
          controller: panelController,
          minHeight: state.minDrawerHeight,
          maxHeight: state.maxDrawerHeight,
          body: const _SendDarkBackdrop(),
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
                      margin: const EdgeInsets.only(top: 10, bottom: 0),
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

class _SendDarkBackdrop extends StatelessWidget {
  const _SendDarkBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF07090F),
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.2,
          colors: [
            Color(0x1F3B82F6),
            Color(0xFF07090F),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _SendBackdropPainter()),
            ),
          ),
          const Center(
            child: _SendLoadingCard(
              title: 'Preparing Send',
              body: 'Loading your delivery workspace.',
            ),
          ),
        ],
      ),
    );
  }
}

class _SendLoadingCard extends StatelessWidget {
  final String title;
  final String body;

  const _SendLoadingCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xD90B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: .12),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .68),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SendBackdropPainter extends CustomPainter {
  const _SendBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: .035)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 42) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var x = 0.0; x < size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
