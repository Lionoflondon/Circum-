import 'package:circum/app/authentication/bloc/auth_bloc.dart';
import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/utils/theme/text_field.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';

import '../../../utils/theme/theme.dart';
import 'delivery_review.dart';

class ChooseAddressView extends StatefulWidget {
  const ChooseAddressView({Key? key}) : super(key: key);

  @override
  ChooseAddressViewState createState() => ChooseAddressViewState();
}

class ChooseAddressViewState extends State<ChooseAddressView> {
  TextEditingController sourceQueryController = TextEditingController();
  TextEditingController destinationQueryController = TextEditingController();
  late FocusNode sourceFocusNode;
  late FocusNode destinationFocusNode;

  @override
  void initState() {
    super.initState();
    sourceFocusNode = FocusNode();
    destinationFocusNode = FocusNode();
  }

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
    sourceFocusNode.dispose();
    destinationFocusNode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: AppColors.secondary,
        elevation: 0,
        title: AppText.text('Where is your package going?',
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
      ),
      body: SafeArea(
          child: Column(
        children: [addresses(), searchResult()],
      )),
    );
  }

  Widget addresses() {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Container(
                height: 85,
                child: Column(
                  children: [
                    Icon(
                      Icons.circle,
                      color: Color(0xFF2D89D4),
                      size: 10,
                    ),
                    Expanded(
                        child: DottedLine(
                      direction: Axis.vertical,
                      dashColor: Color(0xFF1F292E),
                    )),
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: Color(0xFF65C436),
                    ),
                  ],
                )),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
              children: [
                AppTextInput.input(
                    hintText: 'Choose pick up location',
                    focusNode: sourceFocusNode,
                    autofocus: true,
                    controller: sourceQueryController,
                    onChanged: (val) {
                      context.read<SendPackageBloc>().add(SearchAPlaceEvent(
                          query: val,
                          lang: Localizations.localeOf(context).languageCode));
                    }),
                const SizedBox(height: 12),
                AppTextInput.input(
                    focusNode: destinationFocusNode,
                    controller: destinationQueryController,
                    hintText: 'Choose recipient’s location',
                    onChanged: (val) {
                      context.read<SendPackageBloc>().add(SearchAPlaceEvent(
                          query: val,
                          lang: Localizations.localeOf(context).languageCode));
                    })
              ],
            ))
          ],
        ));
  }

  Widget findOut() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24).copyWith(top: 60),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFFEE6352), Color(0xFF2D89D4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText.text('Want to send your package overseas?',
                          fontSize: 16, fontWeight: FontWeight.bold),
                      const SizedBox(height: 10),
                      AppText.text(
                          'Compare courier service prices to find out which works for you. '),
                      const SizedBox(height: 40),
                      TextButton(
                        onPressed: () {},
                        child: Row(
                          children: [
                            AppText.text('Find out more',
                                fontSize: 12, fontWeight: FontWeight.w600),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                            )
                          ],
                        ),
                      )
                    ]),
              ),
              Image(
                image: AssetImage('assets/images/drone_image.png'),
                width: 100,
              )
            ],
          ));
    });
  }

  Widget searchResult() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      if (sourceQueryController.text.isEmpty) {
        return findOut();
      }
      return Expanded(
          child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 20),
        itemBuilder: (context, index) => ListTile(
          leading: SvgPicture.asset(
            'assets/svg/location.svg',
          ),
          minLeadingWidth: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText.text(state.suggestions[index].mainText,
                  fontSize: 16, fontWeight: FontWeight.w600),
              AppText.text(state.suggestions[index].subText,
                  color: const Color(0xFFC9D2D7), fontSize: 12),
            ],
          ),
          onTap: () {
            if (sourceFocusNode.hasFocus) {
              context.read<SendPackageBloc>().add(SetPickupAddress(
                    val: state.suggestions[index].mainText,
                    pickupLocationSubAddress: state.suggestions[index].subText,
                    lang: Localizations.localeOf(context).languageCode,
                    placeId: state.suggestions[index].placeId,
                  ));
              sourceQueryController.text = state.suggestions[index].mainText;
              destinationQueryController.text = '';
              destinationFocusNode.requestFocus();
              context.read<SendPackageBloc>().add(ClearSuggestions());
            }

            if (destinationFocusNode.hasFocus) {
              context.read<SendPackageBloc>().add(SetDeliveryAddress(
                    val: state.suggestions[index].mainText,
                    destinationLocationSubAddress:
                        state.suggestions[index].subText,
                    lang: Localizations.localeOf(context).languageCode,
                    placeId: state.suggestions[index].placeId,
                  ));
              destinationQueryController.text =
                  state.suggestions[index].mainText;

              context.read<SendPackageBloc>().add(ClearSuggestions());
              // destinationFocusNode.requestFocus();

              if (state.pickupLocation != null &&
                  state.pickupLocation!.isNotEmpty) {
                context.read<SendPackageBloc>().add(const SetDeliveryStatus(
                    deliveryStatus: DeliveryStatus.addressesSelected));

                Navigator.pop(context);
                // Navigator.pushReplacement(context,
                //     MaterialPageRoute(builder: (_) => DeliveryReviewView()));
              }
            }
          },
        ),
        itemCount: state.suggestions.length,
      ));
    });
  }
}
