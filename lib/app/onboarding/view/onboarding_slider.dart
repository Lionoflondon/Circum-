import 'dart:async';

// import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../../../utils/theme/theme.dart';

class OnboardingSlider extends StatefulWidget {
  const OnboardingSlider({Key? key}) : super(key: key);

  @override
  OnboardingSliderState createState() => OnboardingSliderState();
}

class OnboardingSliderState extends State<OnboardingSlider>
    with SingleTickerProviderStateMixin {
  late TabController onBoardingTab;
  final sideDuration = const Duration(milliseconds: 300);
  bool selected = false;

  int currentTabIndex = 0;
  // double

  late Timer timer;

  @override
  initState() {
    super.initState();
    onBoardingTab = TabController(length: 3, vsync: this, initialIndex: 0);
    onBoardingTab.addListener(_tabListener);
    // timer = Timer.periodic(const Duration(seconds: 5), (Timer t) {
    //   // print("Somethingy");
    //   changeIndex();
    // });
  }

  @override
  void dispose() {
    timer.cancel();
    onBoardingTab.dispose();
    super.dispose();
  }

  changeIndex() {
    // {setState((){selected = !selected;})}
    // print("Something");
    switch (onBoardingTab.index) {
      case 0:
        {
          onBoardingTab.animateTo(1);
          setState(() {
            currentTabIndex = 1;
          });
        }
        break;

      case 1:
        {
          onBoardingTab.animateTo(2);
          setState(() {
            currentTabIndex = 2;
          });
        }
        break;

      case 2:
        {
          onBoardingTab.animateTo(0);
          setState(() {
            currentTabIndex = 0;
          });
        }
        break;
    }
  }

  _tabListener() {
    // print(onBoardingTab.animation.value.sign);
    setState(() {
      currentTabIndex = onBoardingTab.index;
    });
  }

  Widget onboardingPage({screenWidth, screenHeight, image, widget}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
              color: Color(0xFFEDF3F8),
              child: Container(
                margin: EdgeInsets.only(
                    left: screenWidth * 0.15,
                    right: screenWidth * 0.15,
                    top: MediaQuery.of(context).viewPadding.top + 30),
                width: screenWidth,
                decoration: BoxDecoration(
                    image: DecorationImage(
                        fit: BoxFit.fitWidth, image: AssetImage(image))),
              )),
        ),
        widget
      ],
    );
  }

  Widget _progressIndicator() {
    return Container(
        margin: const EdgeInsets.only(bottom: 20, top: 20),
        // color: const Color(0xFFEDF3F8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: sideDuration,
            height: 8,
            width: 8,
            // width: currentTabIndex == 0 ? 20 : 8,
            decoration: BoxDecoration(
                color: currentTabIndex == 0
                    ? AppColors.primary
                    : AppColors.primary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(20)),
            child: Container(),
          ),
          const SizedBox(width: 5),
          AnimatedContainer(
            duration: sideDuration,
            height: 8,
            width: 8,
            // width: currentTabIndex == 1 ? 20 : 8,
            decoration: BoxDecoration(
                color: currentTabIndex == 1
                    ? AppColors.primary
                    : AppColors.primary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(20)),
            child: Container(),
          ),
          const SizedBox(width: 5),
          AnimatedContainer(
            duration: sideDuration,
            height: 8,
            width: 8,
            // width: currentTabIndex == 2 ? 20 : 8,
            decoration: BoxDecoration(
                color: currentTabIndex == 2
                    ? AppColors.primary
                    : AppColors.primary.withOpacity(0.4),
                borderRadius: BorderRadius.circular(20)),
            child: Container(),
          ),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      Expanded(
          child: SizedBox(
              // height: (MediaQuery.of(context).size.width * 0.6) + 160,
              child: ScrollConfiguration(
                  behavior: const ScrollBehavior().copyWith(overscroll: false),
                  child: TabBarView(
                      physics: const ClampingScrollPhysics(),
                      controller: onBoardingTab,
                      children: [
                        onboardingPage(
                            screenHeight: screenHeight,
                            screenWidth: screenWidth,
                            image: 'assets/images/o_package.png',
                            widget: onboardingText()[0]),
                        onboardingPage(
                          screenHeight: screenHeight,
                          screenWidth: screenWidth,
                          image: 'assets/images/o_package.png',
                          widget: onboardingText()[1],
                        ),
                        onboardingPage(
                            screenHeight: screenHeight,
                            screenWidth: screenWidth,
                            image: 'assets/images/o_package.png',
                            widget: onboardingText()[2]),
                      ])))),
      _progressIndicator(),
    ]);
  }

  onboardingText() {
    return [
      Container(
          margin: const EdgeInsets.only(bottom: 20, left: 30, right: 30),
          child: Column(
            children: [
              const SizedBox(height: 30),
              AppText.text("Effortlessly send and receive packages.",
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDarkMode),
              const SizedBox(height: 16),
              AppText.text(
                "With Circum's intuitive user interface, you can quickly request courier services, track your packages, and communicate with your delivery person - all in one place.",
              )
            ],
          )),
      Container(
          margin: const EdgeInsets.only(bottom: 20, left: 30, right: 30),
          child: Column(
            children: [
              const SizedBox(height: 30),
              AppText.text("Effortlessly send and receive packages.",
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDarkMode),
              const SizedBox(height: 16),
              AppText.text(
                "With Circum's intuitive user interface, you can quickly request courier services, track your packages, and communicate with your delivery person - all in one place.",
              )
            ],
          )),
      Container(
          margin: const EdgeInsets.only(bottom: 20, left: 30, right: 30),
          child: Column(
            children: [
              const SizedBox(height: 30),
              AppText.text("Effortlessly send and receive packages.",
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDarkMode),
              const SizedBox(height: 16),
              AppText.text(
                "With Circum's intuitive user interface, you can quickly request courier services, track your packages, and communicate with your delivery person - all in one place.",
              )
            ],
          )),
    ];
  }
}
