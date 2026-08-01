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
  const AccountDetails({super.key});

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
        body: SafeArea(
            child: BlocListener<AuthBloc, AuthState>(
                listener: (context, state) async {
                  if (state.currentState == AppState.unauthenticated) {
                    // Navigator.pushAndRemoveUntil(
                    //   context,
                    //   MaterialPageRoute(builder: (context) => OnboardingView()),
                    //   (route) => false, // Remove all existing routes
                    // );
                    Navigator.popUntil(context, (route) => route.isFirst);
                    // await Future.delayed(const Duration(milliseconds: 500));
                    // // ignore: use_build_context_synchronously
                    // Navigator.of(context).pushReplacement(
                    //     MaterialPageRoute(builder: (_) => App()));
                  }
                },
                child: Column(children: [
                  _loader(),
                  Expanded(
                      child: Column(
                    children: [
                      header(),
                      firstName(),
                      Divider(
                          height: 10,
                          thickness: 1,
                          color: Colors.white.withValues(alpha: 0.15)),
                      surname(),
                      Divider(
                          height: 10,
                          thickness: 1,
                          color: Colors.white.withValues(alpha: 0.15)),
                      email(),
                      Divider(
                          height: 10,
                          thickness: 1,
                          color: Colors.white.withValues(alpha: 0.15)),
                      phone(),
                      const Spacer(),
                      logout(),
                      deleteAccount(),
                    ],
                  ))
                ]))));
  }

  Widget _loader() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return state.status == Status.loading
          ? LinearProgressIndicator(
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.7),
            )
          : Container();
    });
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
                        final imageBytes = await image.readAsBytes();
                        // ignore: use_build_context_synchronously
                        context.read<AuthBloc>().add(
                            UpdateUserProfilePhoto(imageBytes: imageBytes));
                      }
                    }
                    if (imageSource == 'camera') {
                      XFile? image = await picker.pickImage(
                          source: ImageSource.camera, imageQuality: 1);
                      if (image != null) {
                        final imageBytes = await image.readAsBytes();
                        // ignore: use_build_context_synchronously
                        context.read<AuthBloc>().add(
                            UpdateUserProfilePhoto(imageBytes: imageBytes));
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
                color: Colors.white.withValues(alpha: 0.15),
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
                color: Colors.white.withValues(alpha: 0.15),
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
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.text('Email address',
                      color: AppColors.textGrey, fontSize: 12),
                  AppText.text('${state.email}',
                      fontSize: 16, color: AppColors.textGrey)
                ],
              ),
            )
          : Container();
    });
  }

  Widget phone() {
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
                  AppText.text('Phone number',
                      color: AppColors.textGrey, fontSize: 12),
                  AppText.text(state.phoneNumber ?? '+ Add a phone number',
                      fontSize: 16, color: AppColors.textGrey)
                ],
              ),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                color: Colors.white.withValues(alpha: 0.15),
              )
            ],
          ),
          onPressed: () async {
            String? newPhone = await showEditBottomSheet(context,
                title: 'Phone number', val: state.phoneNumber ?? '');

            if (newPhone != null) {
              // ignore: use_build_context_synchronously
              context.read<AuthBloc>().add(UpdatePhoneNumber(value: newPhone));
            }
          });
    });
  }

  Widget logout() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Padding(
          padding: const EdgeInsets.only(bottom: 0),
          child: TextButton(
            style: TextButton.styleFrom(
                backgroundColor: AppColors.danger.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(),
                padding: const EdgeInsets.symmetric(vertical: 20)),
            onPressed: () {
              context.read<AuthBloc>().add(SignOut());
            },
            child: Center(
                child: AppText.text('Logout',
                    color: Colors.white, fontWeight: FontWeight.w500)),
          ));
    });
  }

  Widget deleteAccount() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      // if (state.status == Status.success) {
      //   context.read<AuthBloc>().add(ResetStatus());
      //   SchedulerBinding.instance.addPostFrameCallback((_) {
      //     Navigator.push(
      //         context,
      //         MaterialPageRoute(
      //             builder: (_) => EnterOTPView(
      //                   deleteAccount: true,
      //                 )));
      //   });
      // }
      return Padding(
          padding: const EdgeInsets.only(bottom: 0),
          child: TextButton(
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20)),
            onPressed: () async {
              final deleteAccount = await deleteAccountBottomSheet(context);

              if (deleteAccount == true) {
                // ignore: use_build_context_synchronously
                context.read<AuthBloc>().add(DeleteAccount());
              }
            },
            child: Center(
                child: AppText.text('Delete Account', color: AppColors.danger)),
          ));
    });
  }

  deleteAccountBottomSheet(context) {
    return showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) {
          return Container(
            decoration: const BoxDecoration(
              color: AppColors.secondary,
            ),
            height: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AppText.text('You cannot reverse this action!',
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                        onPressed: () async {
                          Navigator.pop(context, true);
                        },
                        child: const Row(
                          children: [
                            Icon(Icons.delete_forever, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete account',
                                style: TextStyle(color: Colors.red))
                          ],
                        )),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Divider()),
                    TextButton(
                        onPressed: () async {
                          Navigator.pop(context, false);
                        },
                        child: const Row(children: [
                          Icon(
                            Icons.close,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6),
                          Text('Cancel', style: TextStyle(color: Colors.white))
                        ])),
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 20)
                  ],
                ),
              ],
            ),
          );
        });
  }
}
