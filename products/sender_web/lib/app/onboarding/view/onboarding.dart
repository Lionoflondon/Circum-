import 'dart:io' show Platform;

// import 'package:circum/app/authentication/view/add_details.dart';
import 'package:circum/app/authentication/view/signup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/theme/theme.dart';
import '../../authentication/bloc/auth_bloc.dart';
import '../../authentication/view/enable_location.dart';
import 'onboarding_slider.dart';

class OnboardingView extends StatelessWidget {
  // final BuildContext authBlocContext;
  const OnboardingView({Key? key}) : super(key: key);

  static Page<void> page() => const MaterialPage<void>(child: OnboardingView());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.secondary,
        body: BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              // if (state.status == Status.signedInWithOAuth) {
              //   context.read<AuthBloc>().add(ResetStatus());

              //   Navigator.push(
              //     context,
              //     MaterialPageRoute(builder: (_) => const EnableLocation()),
              //   );
              // }

              // if (state.authenticatedStatus ==
              //     AuthenticatedStatus.incompleteData) {
              //   context.read<AuthBloc>().add(ResetStatus());
              //   // context.read<AuthBloc>().add(StartCountDown());
              //   Navigator.push(context,
              //       MaterialPageRoute(builder: (_) => const AddDetailsView()));
              // }
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(child: OnboardingSlider()),
                Container(
                    // margin: const EdgeInsets.only(bottom: 30),
                    width: MediaQuery.of(context).size.width * 0.9,
                    padding: const EdgeInsets.only(
                        top: 20, bottom: 5, left: 10, right: 10),
                    child: Column(
                      children: [
                        actionButton(),
                        const SizedBox(height: 14),
                        orSignUpWith(),
                        const SizedBox(height: 14),
                        oAuthButtons(),
                        const SizedBox(height: 10),
                        termsOfService()
                      ],
                    )),
                const SizedBox(height: 10),
              ],
            )));
  }

  Widget actionButton() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return AppButton.button(
        onPressed: () {
          // context
          //     .read<AuthBloc>()
          // print('pressing');
          // context
          //     .read<AuthBloc>()
          //     .add(ChangeSelectedPage(page: SelectedPage.cta));
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SignupView()));
        },
        widget: Center(
            child: AppText.text(
          'Continue',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        )),
        borderRadius: BorderRadius.circular(100),
        // minimumSize: const Size(70, 70)
      );
    });
  }

  Widget orSignUpWith() {
    return Row(
      children: [
        const Expanded(child: Divider(color: Colors.grey)),
        const SizedBox(width: 10),
        AppText.text('or continue with', fontSize: 16),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: Colors.grey)),
      ],
    );
  }

  Widget oAuthButtons() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Row(
        children: [
          Expanded(
              child: TextButton(
                  onPressed: () {
                    context.read<AuthBloc>().add(SignInWithGoogle());
                  },
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                          side: BorderSide(
                              color: Colors.white.withOpacity(0.4)))),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset('assets/sender/svg/google_logo.svg'),
                        const SizedBox(width: 12),
                        AppText.text('Google',
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)
                      ]))),
          if (!kIsWeb && Platform.isIOS) const SizedBox(width: 15),
          if (!kIsWeb && Platform.isIOS)
            Expanded(
                child: TextButton(
                    onPressed: () {
                      context.read<AuthBloc>().add(SignInWithAppleAuth());
                    },
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                            side: BorderSide(
                                color: Colors.white.withOpacity(0.4)))),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset('assets/sender/svg/apple_logo.svg'),
                          const SizedBox(width: 12),
                          AppText.text('Apple',
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)
                        ]))),
        ],
      );
    });
  }

  Widget termsOfService() {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            GestureDetector(
                onTap: () async {
                  await launchUrl(Uri.parse('https://circumuk.com/terms'));
                },
                child: AppText.text('By signing up, you are agreeing to our',
                    fontSize: 12)),
            GestureDetector(
                onTap: () async {
                  await launchUrl(Uri.parse('https://circumuk.com/terms'));
                },
                child: AppText.text('Terms of Service',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color.fromARGB(255, 203, 232, 255))),
          ],
        ));
  }
}
