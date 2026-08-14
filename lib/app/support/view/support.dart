import 'package:circum/app/support/view/faq.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../send_package/view/ride_chats.dart';
import '../../sender_mobile/design_system/sender_design_system.dart';
import '../../../utils/theme/theme.dart';
import '../bloc/support_bloc.dart';

class SupportView extends StatelessWidget {
  const SupportView({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTokens.background, AppTokens.midnight],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [appBar(context), const SizedBox(height: 28), options()],
      ),
    );
  }

  Widget appBar(context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 16, 20, 0),
      child: AppGlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        accent: AppTokens.primary,
        child: Row(
          children: [
            const Icon(Icons.support_agent_rounded,
                color: AppTokens.primaryLight),
            const SizedBox(width: 12),
            Text('CIRCUM Support',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTokens.text,
                      fontWeight: FontWeight.w800,
                    )),
          ],
        ),
      ),
    );
  }

  Widget options() {
    return BlocBuilder<SupportBloc, SupportState>(builder: (context, state) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: AppGlassContainer(
          padding: EdgeInsets.zero,
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
                          const Icon(Icons.forum_rounded,
                              color: AppTokens.primaryLight),
                          const SizedBox(width: 16),
                          AppText.text(
                            'Live Chat',
                          )
                        ],
                      ),
                      Icon(
                        Icons.keyboard_arrow_right_rounded,
                        color: Colors.white.withValues(alpha: 0.15),
                      )
                    ],
                  ),
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RideChatPageView(
                                  title: 'Circum Support',
                                  supportConversation: true,
                                )));
                  }),
              Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.15)),
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
                          const Icon(Icons.help_outline_rounded,
                              color: AppTokens.primaryLight),
                          const SizedBox(width: 16),
                          AppText.text(
                            'FAQ',
                          )
                        ],
                      ),
                      Icon(
                        Icons.keyboard_arrow_right_rounded,
                        color: Colors.white.withValues(alpha: 0.15),
                      )
                    ],
                  ),
                  onPressed: () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const FAQView()));
                  }),
            ],
          ),
        ),
      );
    });
  }
}
