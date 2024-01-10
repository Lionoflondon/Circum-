import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';

import '../../../utils/theme/theme.dart';
import '../../account/view/account.dart';
import '../../authentication/bloc/auth_bloc.dart';
import '../../history/view/index.dart';
import '../../send_package/view/index.dart';
import '../../send_package/view/maps_view.dart';
import '../../support/view/index.dart';
import '../bloc/navbar_bloc.dart';

class AppNavView extends StatefulWidget {
  AppNavView({Key? key}) : super(key: key);

  @override
  AppNavState createState() => AppNavState();
}

class AppNavState extends State<AppNavView> {
  AuthBloc? authBloc;

  @override
  void initState() {
    super.initState();
    authBloc = context.read<AuthBloc>();
    authBloc?.add(RequestLocationData());
    // Timer.periodic(const Duration(seconds: 20),
    //     (timer) => authBloc?.add(RequestLocationData()));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavbarBloc, NavbarState>(builder: (context, state) {
      return Scaffold(
        backgroundColor: AppColors.secondary,
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(child: MapsView()),
                const SizedBox(height: 180),
              ],
            ),
            if (state.currentNavIndex >= 0) userScreens(context, 0),
            // Column(
            //   mainAxisAlignment: MainAxisAlignment.end,
            //   children: [
            //     if (state.currentNavIndex >= 0) userScreens(context, 0),
            //   ],
            // ),
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
              icon: Container(
                height: 22,
                width: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  color: AppColors.input,
                ),
                child: authBloc != null &&
                        authBloc!.state.profilePhoto != null &&
                        authBloc!.state.profilePhoto != ''
                    ? CachedNetworkImage(
                        imageUrl: authBloc!.state.profilePhoto!,
                        imageBuilder: (context, imageProvider) => Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(100),
                            image: DecorationImage(
                              image: imageProvider,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        placeholder: (context, url) => Container(),
                        //     CircularProgressIndicator(
                        //   color: Colors.grey,
                        // ),
                        errorWidget: (context, url, error) => Icon(Icons.error),
                      )
                    : SvgPicture.asset(
                        'assets/svg/account.svg',
                        height: 32,
                      ),
              ),
            ),
          ],
        ),
      );

  Widget userScreens(context, index) {
    List<Widget> children = [
      const HomeView(),
      const HistoryView(),
      const SupportView(),
      const AccountView(),
    ];
    return children[index];
  }
}
