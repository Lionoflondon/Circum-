import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_maps_widget/google_maps_widget.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../helper/google_map_controller.dart';
import '../../../utils/theme/theme.dart';
import '../../account/view/account.dart';
import '../../history/view/index.dart';
import '../../home/view/index.dart';
import '../../support/view/index.dart';
import '../bloc/navbar_bloc.dart';

class AppNavView extends StatelessWidget {
  AppNavView({Key? key}) : super(key: key);

  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(55.838175, -4.272892),
    zoom: 14.4746,
  );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavbarBloc, NavbarState>(builder: (context, state) {
      return Scaffold(
        backgroundColor: AppColors.secondary,
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                    child: GoogleMap(
                  mapType: MapType.normal,
                  initialCameraPosition: _kGooglePlex,
                  onMapCreated: !_controller.isCompleted
                      ? (GoogleMapController controller) {
                          // MapControllerSingleton().setController(controller);
                        }
                      : null,
                )),
                if (state.currentNavIndex >= 0) userScreens(context, 0),
              ],
            ),
            if (state.currentNavIndex > 0)
              Column(
                children: [
                  Expanded(child: userScreens(context, state.currentNavIndex)),
                ],
              )
          ],
        ),
        bottomNavigationBar: _buildBottomNavigation(),
      );
    });
  }

  Widget _buildBottomNavigation() => BlocBuilder<NavbarBloc, NavbarState>(
        builder: (context, state) => BottomNavigationBar(
          elevation: 0,
          backgroundColor: const Color(0xFF151A1C),
          // fixedColor: Colors.black,
          currentIndex: state.currentNavIndex,
          selectedFontSize: 10,
          unselectedFontSize: 10,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.grey,
          selectedLabelStyle: const TextStyle(fontFamily: 'OpenSans'),
          unselectedLabelStyle: const TextStyle(fontFamily: 'OpenSans'),
          type: BottomNavigationBarType.fixed,
          onTap: (index) =>
              context.read<NavbarBloc>().add(ChangeTabIndex(index: index)),
          items: [
            BottomNavigationBarItem(
                // backgroundColor: Colors.white,
                label: 'Home',
                activeIcon: SvgPicture.asset(
                  'assets/svg/home.svg',
                  height: 22,
                ),
                icon: SvgPicture.asset(
                  'assets/svg/home.svg',
                  color: AppColors.grey,
                  height: 22,
                )),
            BottomNavigationBarItem(
                label: 'History',
                activeIcon: SvgPicture.asset(
                  'assets/svg/history.svg',
                  color: AppColors.primary,
                  height: 22,
                ),
                icon: SvgPicture.asset(
                  'assets/svg/history.svg',
                  height: 22,
                )),
            BottomNavigationBarItem(
                label: 'Live Chat',
                activeIcon: SvgPicture.asset(
                  'assets/svg/chat.svg',
                  color: AppColors.primary,
                  height: 22,
                ),
                icon: SvgPicture.asset(
                  'assets/svg/chat.svg',
                  height: 22,
                )),
            BottomNavigationBarItem(
              label: 'Account',
              icon: SvgPicture.asset(
                'assets/svg/account.svg',
                height: 22,
              ),
            ),
          ],
        ),
      );

  Widget userScreens(context, index) {
    List<Widget> children = [
      HomeView(),
      const HistoryView(),
      const SupportView(),
      const AccountView(),
    ];
    return children[index];
  }
}
