import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../utils/theme/text_field.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/auth_bloc.dart';

class AddDetailsView extends StatelessWidget {
  const AddDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.secondary,
        body: BlocListener<AuthBloc, AuthState>(
            listener: (context, state) {
              if (state.status == Status.success) {
                context.read<AuthBloc>().add(ResetStatus());

                // Navigator.popUntil(context, (route) => route.isFirst);

                // Navigator.push(
                //   context,
                //   MaterialPageRoute(builder: (_) => const EnableLocation()),
                // );
              }
            },
            child: PopScope(
                canPop: false,
                child: SizedBox(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).padding.top,
                        ),
                        _loader(),
                        Container(
                            width: MediaQuery.of(context).size.width,
                            padding: const EdgeInsets.symmetric(horizontal: 30),
                            margin: const EdgeInsets.only(
                              top: 40,
                            ),
                            child: AppText.text("Add Your Name",
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 24)),
                        const SizedBox(height: 44),
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 30),
                            child: _nameField()),
                        const SizedBox(height: 20),
                        // _lastNameField(),
                        // const SizedBox(height: 20),
                        // _usernameField(),
                        // const SizedBox(height: 20),
                        // _gender(),
                        // const SizedBox(height: 10),
                        const Spacer(),
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 30),
                            child: _errorMessage()),
                        const SizedBox(height: 10),
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 30),
                            child: _nextButton()),
                        const SizedBox(height: 40),
                      ],
                    )))));
  }

  Widget _nameField() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppText.text('Name', color: Colors.white, fontWeight: FontWeight.bold),
        const SizedBox(height: 12),
        AppTextInput.input(
          hintText: 'eg. Phil Knight',
          onChanged: (value) => context.read<AuthBloc>().add(
                UsernameChanged(username: value),
              ),
        )
      ]);
    });
  }

  Widget _errorMessage() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return Container(
          padding:
              EdgeInsets.symmetric(vertical: state.errorMessage == '' ? 0 : 10),
          child: Text(state.errorMessage ?? '',
              style: const TextStyle(color: Colors.red)));
    });
  }

  Widget _nextButton() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return SizedBox(
          // margin: const EdgeInsets.symmetric(horizontal: 30),
          height: 50,
          // width: MediaQuery.of(context).size.width * 0.8,
          child: AppButton.button(
            onPressed: () {
              if (state.username != null && '${state.username}'.trim() != '') {
                context
                    .read<AuthBloc>()
                    .add(UpdateUserProfile(username: state.username!));
              }
            },
            widget: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppText.text("Next",
                    fontWeight: FontWeight.w700, color: Colors.white),
              ],
            ),
            // isLoading: state.status == Status.loading
          ));
    });
  }

  Widget _loader() {
    return BlocBuilder<AuthBloc, AuthState>(builder: (context, state) {
      return state.status == Status.loading
          ? LinearProgressIndicator(color: AppColors.primary)
          : Container();
    });
  }
}
