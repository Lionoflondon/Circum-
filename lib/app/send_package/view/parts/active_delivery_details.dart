import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/app/send_package/view/ride_chats.dart';
import 'package:currency_symbols/currency_symbols.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../utils/theme/theme.dart';

class ActiveDeliveryDetails extends StatefulWidget {
  const ActiveDeliveryDetails({Key? key}) : super(key: key);

  @override
  State<ActiveDeliveryDetails> createState() => _ActiveDeliveryDetailsState();
}

class _ActiveDeliveryDetailsState extends State<ActiveDeliveryDetails> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      // if (state.panelControlStatus == PanelControlStatus.isClosed) {
      //   print('hits here');
      //   panelController.animatePanelToPosition(0);
      //   context
      //       .read<SendPackageBloc>()
      //       .add(SetPanelControlStatus(status: PanelControlStatus.initialized));
      // }
      return Container(
          color: AppColors.secondary,
          child: Column(children: [
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/red_profile_icon.png',
                      height: 36,
                      width: 36,
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText.text(state.deliveryData!.courierName,
                            fontWeight: FontWeight.w600),
                        AppText.text('Rating', color: AppColors.textGrey)
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AppText.text(state.deliveryData!.plateNumber,
                            fontWeight: FontWeight.w600),
                        AppText.text('Type of vehicle',
                            color: AppColors.textGrey)
                      ],
                    ),
                  ],
                )),
            const Divider(
              color: AppColors.borderColor,
              height: 1,
              thickness: 1,
            ),
            Row(
              children: [
                Expanded(
                    child: Column(
                  children: [
                    AppText.text('Estimated delivery time',
                        fontSize: 10, color: AppColors.textGrey),
                    AppText.text('12:54 PM', fontSize: 16)
                  ],
                )),
                Expanded(
                    child: AppButton.button(
                        backgroundColor: AppColors.grey,
                        minimumSize: const Size(0, 99),
                        widget: Column(
                          children: [
                            AppText.text('Call Courier',
                                fontSize: 12, color: AppColors.textGrey),
                            const SizedBox(height: 9),
                            SvgPicture.asset('assets/svg/phone_outline.svg')
                          ],
                        ),
                        onPressed: () {
                          launch("tel://${state.deliveryData!.phoneNumber}");
                        }))
              ],
            ),
            const Divider(
              color: AppColors.borderColor,
              height: 1,
              thickness: 1,
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AppButton.button(
                  backgroundColor: AppColors.grey,
                  widget: Row(
                    children: [
                      const SizedBox(width: 22),
                      AppText.text('Message Courier',
                          fontSize: 12, color: AppColors.textGrey),
                      const Spacer(),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 22),
                    ],
                  ),
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RideChatPageView()));
                  }),
            ),
            const SizedBox(height: 20),
            const Divider(
              color: AppColors.borderColor,
              height: 1,
              thickness: 1,
            ),
            const SizedBox(height: 24),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText.text('Delivery details',
                        fontSize: 16, fontWeight: FontWeight.w600),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        SvgPicture.asset('assets/svg/location.svg'),
                        const SizedBox(width: 18),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText.text('Delivery Address',
                                fontSize: 12, color: AppColors.textGrey),
                            AppText.text('${state.destinationLocation}',
                                fontSize: 16)
                          ],
                        ))
                      ],
                    ),
                    const Divider(
                      color: AppColors.borderColor,
                      height: 32,
                      thickness: 1,
                    ),
                    Row(
                      children: [
                        SvgPicture.asset('assets/svg/wallet.svg'),
                        const SizedBox(width: 18),
                        Expanded(
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText.text('Price',
                                fontSize: 12, color: AppColors.textGrey),
                            AppText.text(
                                '${cSymbol(state.currency)}${state.price}',
                                fontSize: 16)
                          ],
                        ))
                      ],
                    ),
                    if (state.dropoffDetails?.moreInformation != null)
                      const Divider(
                        color: AppColors.borderColor,
                        height: 32,
                        thickness: 1,
                      ),
                    if (state.dropoffDetails?.moreInformation != null)
                      Row(
                        children: [
                          SvgPicture.asset('assets/svg/legal.svg'),
                          const SizedBox(width: 18),
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText.text('Delivery Information',
                                  fontSize: 12, color: AppColors.textGrey),
                              AppText.text(
                                  state.dropoffDetails?.moreInformation ?? '',
                                  fontSize: 16)
                            ],
                          ))
                        ],
                      ),
                  ],
                )),
            const SizedBox(height: 20),
            const Divider(
              color: AppColors.borderColor,
              height: 1,
              thickness: 1,
            ),
            TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                    minimumSize: Size(MediaQuery.of(context).size.width, 60)),
                child: Center(
                  child: AppText.text('Cancel request',
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                )),
          ]));
    });
  }
}
