import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';

import '../../../utils/theme/theme.dart';
import '../bloc/support_bloc.dart';
import 'chat.dart';

class SupportView extends StatelessWidget {
  const SupportView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [appBar(context), const SizedBox(height: 40), options()],
      ),
    );
  }

  Widget appBar(context) {
    return Container(
      margin: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 20, left: 24),
      width: double.maxFinite,
      child: AppText.text('Support',
          color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
    );
  }

  Widget options() {
    return BlocBuilder<SupportBloc, SupportState>(builder: (context, state) {
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
                          SvgPicture.asset('assets/svg/support.svg'),
                          const SizedBox(width: 16),
                          AppText.text(
                            'Live Chat',
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
                            builder: (_) => const ChatPageView()));
                  }),
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
                          SvgPicture.asset('assets/svg/support.svg'),
                          const SizedBox(width: 16),
                          AppText.text(
                            'FAQ',
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
