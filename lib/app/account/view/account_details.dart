import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';

import '../../../utils/app_state/app_state.dart';
import '../../../utils/theme/theme.dart';
import '../../authentication/bloc/auth_bloc.dart';
import 'bottom_sheets/bottom_sheets.dart';
import 'bottom_sheets/image_bs.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
        body: BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              if (state.currentState == AppState.unauthenticated) {
                print('signing out');
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
            child: Column(children: [
              header(),
              firstName(),
              Divider(
                  height: 10,
                  thickness: 1,
                  color: Colors.white.withOpacity(0.15)),
              surname(),
              Divider(
                  height: 10,
                  thickness: 1,
                  color: Colors.white.withOpacity(0.15)),
              email(),
              phone(),
              const Spacer(),
              logout()
            ])));
  }

  Widget header() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
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
                  onTap: () async {
                    final ImagePicker picker = ImagePicker();
                    final imageSource = await showImageBottomSheet(context);
                    if (imageSource == 'library') {
                      XFile? image = await picker.pickImage(
                          source: ImageSource.gallery, imageQuality: 1);
                      if (image != null) {
                        // ignore: use_build_context_synchronously
                        context
                            .read<AuthBloc>()
                            .add(UpdateUserProfilePhoto(imagePath: image.path));
                      }
                    }
                    if (imageSource == 'camera') {
                      XFile? image = await picker.pickImage(
                          source: ImageSource.camera, imageQuality: 1);
                      if (image != null) {
                        // ignore: use_build_context_synchronously
                        context
                            .read<AuthBloc>()
                            .add(UpdateUserProfilePhoto(imagePath: image.path));
                      }
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: MediaQuery.of(context).size.width),
                      Container(
                          height: 56,
                          width: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(100),
                            color: AppColors.input,
                          ),
                          child: state.profilePhoto != null &&
                                  state.profilePhoto != ''
                              ? CachedNetworkImage(
                                  imageUrl: state.profilePhoto!,
                                  imageBuilder: (context, imageProvider) =>
                                      Container(
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
                                  errorWidget: (context, url, error) =>
                                      Icon(Icons.error),
                                )
                              : Stack(
                                  children: [
                                    SvgPicture.asset(
                                      'assets/svg/account.svg',
                                      height: 200,
                                    ),
                                    Align(
                                      alignment: Alignment.center,
                                      child: SvgPicture.asset(
                                          'assets/svg/user.svg'),
                                    )
                                  ],
                                )),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          SvgPicture.asset('assets/svg/edit.svg'),
                          const SizedBox(width: 4),
                          AppText.text('Edit Image',
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)
                        ],
                      )
                    ],
                  )))
        ],
      );
    });
  }

  Widget firstName() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
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
                  AppText.text(
                      state.username != null
                          ? '${state.username}'.trim().split(' ').first
                          : '',
                      fontSize: 16,
                      color: AppColors.textGrey)
                ],
              ),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                color: Colors.white.withOpacity(0.15),
              )
            ],
          ),
          onPressed: () async {
            String? newName = await showEditBottomSheet(context,
                title: 'First name',
                val: state.username != null
                    ? '${state.username}'.trim().split(' ').first
                    : '');

            if (newName != null) {
              // ignore: use_build_context_synchronously
              context.read<AuthBloc>().add(UpdateFirstName(value: newName));
            }
          });
    });
  }

  Widget surname() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
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
                  AppText.text(
                      state.username != null
                          ? '${state.username}'.trim().split(' ').last
                          : '',
                      fontSize: 16,
                      color: AppColors.textGrey)
                ],
              ),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                color: Colors.white.withOpacity(0.15),
              )
            ],
          ),
          onPressed: () async {
            String? newName = await showEditBottomSheet(context,
                title: 'Surname',
                val: state.username != null
                    ? '${state.username}'.trim().split(' ').last
                    : '');

            if (newName != null) {
              // ignore: use_build_context_synchronously
              context.read<AuthBloc>().add(UpdateLastName(value: newName));
            }
          });
    });
  }

  Widget email() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return state.email != null && state.email != ''
          ? TextButton(
              // borderSide: BorderSide.none,
              // backgroundColor: AppColors.secondary,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText.text('Email address',
                          color: AppColors.textGrey, fontSize: 12),
                      AppText.text('${state.email}',
                          fontSize: 16, color: AppColors.textGrey)
                    ],
                  ),
                  Icon(
                    Icons.keyboard_arrow_right_rounded,
                    color: Colors.white.withOpacity(0.15),
                  )
                ],
              ),
              onPressed: () {})
          : Container();
    });
  }

  Widget phone() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return state.phoneNumber != null
          ? TextButton(
              // borderSide: BorderSide.none,
              // backgroundColor: AppColors.secondary,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText.text('Phone number',
                          color: AppColors.textGrey, fontSize: 12),
                      AppText.text('${state.phoneNumber}',
                          fontSize: 16, color: AppColors.textGrey)
                    ],
                  ),
                  Icon(
                    Icons.keyboard_arrow_right_rounded,
                    color: Colors.white.withOpacity(0.15),
                  )
                ],
              ),
              onPressed: () {})
          : Container();
    });
  }

  Widget logout() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: TextButton(
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20)),
            onPressed: () {
              context.read<AuthBloc>().add(SignOut());
            },
            child:
                Center(child: AppText.text('Logout', color: AppColors.danger)),
          ));
    });
  }
}
