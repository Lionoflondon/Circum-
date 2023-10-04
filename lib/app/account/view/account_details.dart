import 'package:circum/app/account/bloc/account_bloc.dart';
import 'package:circum/utils/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'bottom_sheets/bottom_sheets.dart';

class AccountDetails extends StatefulWidget {
  const AccountDetails({Key? key}) : super(key: key);

  @override
  State<AccountDetails> createState() => _AccountDetailsState();
}

class _AccountDetailsState extends State<AccountDetails> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          title: AppText.text('Profile',
              fontSize: 16, fontWeight: FontWeight.bold),
          centerTitle: true,
        ),
        backgroundColor: AppColors.secondary,
        body: Column(children: [
          header(),
          firstName(),
          Divider(
              height: 10, thickness: 1, color: Colors.white.withOpacity(0.15)),
          surname(),
          Divider(
              height: 10, thickness: 1, color: Colors.white.withOpacity(0.15)),
          email(),
          Divider(
              height: 10, thickness: 1, color: Colors.white.withOpacity(0.15)),
          password(),
          const Spacer(),
          logout()
        ]));
  }

  Widget header() {
    return BlocBuilder<AccountBloc, AccountState>(builder: (context, state) {
      return Stack(
        children: [
          Container(
            height: 130,
            // color: AppColors.primary,
          ),
          Container(
            height: 80,
            color: AppColors.primary,
          ),
          Positioned(
              bottom: 0,
              // left: (MediaQuery.of(context).size.width / 2) - 28,
              child: GestureDetector(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: MediaQuery.of(context).size.width),
                  SizedBox(
                      height: 56,
                      width: 56,
                      child: Stack(
                        children: [
                          SvgPicture.asset(
                            'assets/svg/account.svg',
                            height: 200,
                          ),
                          Align(
                            alignment: Alignment.center,
                            child: SvgPicture.asset('assets/svg/user.svg'),
                          )
                        ],
                      )),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SvgPicture.asset('assets/svg/edit.svg'),
                      const SizedBox(width: 4),
                      AppText.text('Edit Image',
                          color: AppColors.primary, fontWeight: FontWeight.w600)
                    ],
                  )
                ],
              )))
        ],
      );
    });
  }

  Widget firstName() {
    return BlocBuilder<AccountBloc, AccountState>(builder: (context, state) {
      return TextButton(
          // borderSide: BorderSide.none,
          // backgroundColor: AppColors.secondary,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.text('First name',
                      color: AppColors.textGrey, fontSize: 12),
                  AppText.text('Joshua',
                      fontSize: 16, color: AppColors.textGrey)
                ],
              ),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                color: Colors.white.withOpacity(0.15),
              )
            ],
          ),
          onPressed: () async {
            String? newName = await showEditFirstNameSheet(context);
          });
    });
  }

  Widget surname() {
    return BlocBuilder<AccountBloc, AccountState>(builder: (context, state) {
      return TextButton(
          // borderSide: BorderSide.none,
          // backgroundColor: AppColors.secondary,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.text('Surname',
                      color: AppColors.textGrey, fontSize: 12),
                  AppText.text('Joshua',
                      fontSize: 16, color: AppColors.textGrey)
                ],
              ),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                color: Colors.white.withOpacity(0.15),
              )
            ],
          ),
          onPressed: () {});
    });
  }

  Widget email() {
    return BlocBuilder<AccountBloc, AccountState>(builder: (context, state) {
      return TextButton(
          // borderSide: BorderSide.none,
          // backgroundColor: AppColors.secondary,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.text('Email address',
                      color: AppColors.textGrey, fontSize: 12),
                  AppText.text('josh@yopmail.com',
                      fontSize: 16, color: AppColors.textGrey)
                ],
              ),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                color: Colors.white.withOpacity(0.15),
              )
            ],
          ),
          onPressed: () {});
    });
  }

  Widget password() {
    return BlocBuilder<AccountBloc, AccountState>(builder: (context, state) {
      return TextButton(
          // borderSide: BorderSide.none,
          // backgroundColor: AppColors.secondary,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.text('Password',
                      color: AppColors.textGrey, fontSize: 12),
                  AppText.text('********',
                      fontSize: 16, color: AppColors.textGrey)
                ],
              ),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                color: Colors.white.withOpacity(0.15),
              )
            ],
          ),
          onPressed: () {});
    });
  }

  Widget logout() {
    return BlocBuilder<AccountBloc, AccountState>(builder: (context, state) {
      return TextButton(
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 20)),
        onPressed: () {},
        child: Center(child: AppText.text('Logout', color: AppColors.danger)),
      );
    });
  }
}
