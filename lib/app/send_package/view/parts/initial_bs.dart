import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../utils/theme/theme.dart';
import '../../bloc/send_package_bloc.dart';
import '../choose_address.dart';

class InitialBS extends StatefulWidget {
  const InitialBS({Key? key}) : super(key: key);

  @override
  State<InitialBS> createState() => _InitialBSState();
}

class _InitialBSState extends State<InitialBS> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      return Column(
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 24),
            child: AppButton.button(
                backgroundColor: AppColors.input,
                widget: Row(
                  children: [
                    const SizedBox(width: 5),
                    SvgPicture.asset('assets/svg/search.svg'),
                    const SizedBox(width: 16),
                    AppText.text('Where to?',
                        color: Colors.white.withOpacity(0.3))
                  ],
                ),
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ChooseAddressView()));
                  // setState(() {});
                }),
          ),
          const SizedBox(height: 36),
          if (state.ongoingRequests.length > 0)
            SizedBox(
                width: double.maxFinite,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: AppText.text('Ongoing Requests',
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemBuilder: (contxt, index) {
                          return TextButton(
                              // borderSide: BorderSide.none,
                              // backgroundColor: AppColors.secondary,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 5),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    children: [
                                      AppText.text('Placeholder Address',
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600),
                                      AppText.text('Placeholder subaddress',
                                          color: AppColors.textGrey)
                                    ],
                                  ),
                                  Icon(
                                    Icons.keyboard_arrow_right_rounded,
                                    color: Colors.white.withOpacity(0.15),
                                  )
                                ],
                              ),
                              onPressed: () {});
                        },
                        separatorBuilder: (_, i) => Divider(
                            height: 5,
                            thickness: 1,
                            color: Colors.white.withOpacity(0.15)),
                        itemCount: state.ongoingRequests.length)
                  ],
                )),
          const SizedBox(height: 24),
        ],
      );
    });
  }
}
