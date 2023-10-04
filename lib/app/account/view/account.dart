import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../utils/theme/theme.dart';
import '../bloc/account_bloc.dart';
import 'account_details.dart';

class AccountView extends StatelessWidget {
  const AccountView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
        color: AppColors.secondary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [appBar(context), const SizedBox(height: 40), options()],
        ));
  }

  Widget appBar(context) {
    return Container(
        margin: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 20, left: 24),
        width: double.maxFinite,
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/svg/account.svg',
              height: 32,
            ),
            const SizedBox(width: 16),
            AppText.text('Moses',
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          ],
        ));
  }

  Widget options() {
    return BlocBuilder<AccountBloc, AccountState>(builder: (context, state) {
      return SizedBox(
          width: double.maxFinite,
          child: Column(
            children: [
              TextButton(
                  // borderSide: BorderSide.none,
                  // backgroundColor: AppColors.secondary,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          SvgPicture.asset('assets/svg/profile.svg'),
                          const SizedBox(width: 16),
                          AppText.text(
                            'Profile',
                          )
                        ],
                      ),
                      Icon(
                        Icons.keyboard_arrow_right_rounded,
                        color: Colors.white.withOpacity(0.15),
                      )
                    ],
                  ),
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AccountDetails()));
                  }),
              // Divider(
              //     height: 1,
              //     thickness: 1,
              //     color: const Color.fromRGBO(255, 255, 255, 1).withOpacity(0.15)),
              // TextButton(
              //     // borderSide: BorderSide.none,
              //     // backgroundColor: AppColors.secondary,
              //     style: TextButton.styleFrom(
              //       padding: const EdgeInsets.symmetric(
              //           horizontal: 24, vertical: 16),
              //     ),
              //     child: Row(
              //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
              //       children: [
              //         Row(
              //           children: [
              //             SvgPicture.asset('assets/svg/earnings.svg'),
              //             const SizedBox(width: 16),
              //             AppText.text(
              //               'Earnings',
              //             )
              //           ],
              //         ),
              //         Icon(
              //           Icons.keyboard_arrow_right_rounded,
              //           color: Colors.white.withOpacity(0.15),
              //         )
              //       ],
              //     ),
              //     onPressed: () {}),
              Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.white.withOpacity(0.15)),
              TextButton(
                  // borderSide: BorderSide.none,
                  // backgroundColor: AppColors.secondary,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          SvgPicture.asset('assets/svg/share.svg'),
                          const SizedBox(width: 16),
                          AppText.text(
                            'Share',
                          )
                        ],
                      ),
                      Icon(
                        Icons.keyboard_arrow_right_rounded,
                        color: Colors.white.withOpacity(0.15),
                      )
                    ],
                  ),
                  onPressed: () {}),
              Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.white.withOpacity(0.15)),
              TextButton(
                  // borderSide: BorderSide.none,
                  // backgroundColor: AppColors.secondary,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          SvgPicture.asset('assets/svg/legal.svg'),
                          const SizedBox(width: 16),
                          AppText.text(
                            'Legal',
                          )
                        ],
                      ),
                      Icon(
                        Icons.keyboard_arrow_right_rounded,
                        color: Colors.white.withOpacity(0.15),
                      )
                    ],
                  ),
                  onPressed: () {}),
            ],
          ));
    });
  }
}
