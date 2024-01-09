import 'package:bot_toast/bot_toast.dart';
import 'package:circum/app/authentication/bloc/auth_bloc.dart';
import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/app/send_package/models/contact_info.dart';
import 'package:circum/utils/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_keyboard_size/flutter_keyboard_size.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_svg/svg.dart';

import '../../../utils/theme/text_field.dart';

class DeliveryReviewExpandedView extends StatefulWidget {
  DeliveryReviewExpandedView({Key? key}) : super(key: key);

  @override
  State<DeliveryReviewExpandedView> createState() =>
      _DeliveryReviewExpandedViewState();
}

class _DeliveryReviewExpandedViewState
    extends State<DeliveryReviewExpandedView> {
  final TextEditingController _textFieldController = TextEditingController();

  String? username;
  String? phoneNumber;
  String? additonalPickupInformation;
  String? additonalDeliveryInformation;

  String? dropoffContactName;
  String? dropoffContactPhoneNumber;
  String? dropoffAdditionalInformation;
  @override
  void initState() {
    final AuthBloc authBloc = context.read<AuthBloc>();
    username = authBloc.state.username;
    phoneNumber = authBloc.state.phoneNumber;
    print('phoneNumber is ${authBloc.state.phoneNumber}');
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: AppColors.secondary,
        elevation: 0,
        centerTitle: true,
        title: AppText.text('Review delivery',
            fontSize: 16, fontWeight: FontWeight.bold),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    pickupDetail(),
                    const SizedBox(height: 52),
                    dropOffDetails(),
                  ],
                ))),
        confirmDeliveryButton()
      ]),
    );
  }

  Widget pickupDetail() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(left: 24),
              child: AppText.text('Pick-up details',
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          ListTile(
              onTap: () async {
                _textFieldController.text = username ?? '';
                final String? contactName =
                    await additioalDetailsBottomSheet(title: 'Contact name');

                if (contactName != null) {
                  setState(() {
                    username = contactName;
                  });
                }
              },
              dense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 24),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      SvgPicture.asset(
                        'assets/svg/profile.svg',
                        height: 32,
                        width: 32,
                      ),
                      const SizedBox(width: 18),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText.text('Contact name',
                              color: const Color(0xFFC9D2D7), fontSize: 12),
                          AppText.text(username ?? '', fontSize: 16)
                        ],
                      )
                    ],
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Color(0xFF415058),
                  )
                ],
              )),
          const SizedBox(height: 20),
          ListTile(
              onTap: () {},
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                      child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/svg/location.svg',
                        height: 32,
                        width: 32,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText.text('Address',
                              color: const Color(0xFFC9D2D7), fontSize: 12),
                          AppText.text(
                              '${state.pickupLocation}, ${state.pickupLocationSubAddress}',
                              fontSize: 16)
                        ],
                      ))
                    ],
                  )),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Color(0xFF415058),
                  )
                ],
              )),
          const SizedBox(height: 20),
          ListTile(
              onTap: () {},
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                      child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/svg/phone.svg',
                        height: 32,
                        width: 32,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText.text('Phone number',
                              color: const Color(0xFFC9D2D7), fontSize: 12),
                          AppText.text(phoneNumber ?? '', fontSize: 16)
                        ],
                      ))
                    ],
                  )),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Color(0xFF415058),
                  )
                ],
              )),
          const SizedBox(height: 20),
          ListTile(
              onTap: () async {
                _textFieldController.text = additonalPickupInformation ?? '';
                final String? info = await additioalDetailsBottomSheet(
                    title: 'More information');

                if (info != null) {
                  setState(() {
                    additonalPickupInformation = info;
                  });
                }
              },
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                      child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/svg/legal.svg',
                        height: 32,
                        width: 32,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText.text('More information',
                              color: const Color(0xFFC9D2D7), fontSize: 12),
                          AppText.text(
                              additonalPickupInformation ??
                                  'Add an additional information',
                              fontSize: 16,
                              color: additonalPickupInformation != null
                                  ? Colors.white
                                  : const Color(0xFFC9D2D7))
                        ],
                      ))
                    ],
                  )),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Color(0xFF415058),
                  )
                ],
              )),
        ],
      );
    });
  }

  Widget dropOffDetails() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.only(left: 24),
              child: AppText.text('Drop-off details',
                  fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          ListTile(
              onTap: () async {
                _textFieldController.text = dropoffContactName ?? '';
                final String? info =
                    await additioalDetailsBottomSheet(title: 'Contact name');

                if (info != null) {
                  setState(() {
                    dropoffContactName = info;
                  });
                }
              },
              dense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 24),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      SvgPicture.asset(
                        'assets/svg/profile.svg',
                        height: 32,
                        width: 32,
                      ),
                      const SizedBox(width: 18),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText.text('Contact name',
                              color: const Color(0xFFC9D2D7), fontSize: 12),
                          AppText.text(dropoffContactName ?? 'Full name',
                              fontSize: 16,
                              color: dropoffContactName != null
                                  ? Colors.white
                                  : const Color(0xFFC9D2D7))
                        ],
                      )
                    ],
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Color(0xFF415058),
                  )
                ],
              )),
          const SizedBox(height: 20),
          ListTile(
              onTap: () {},
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                      child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/svg/location.svg',
                        height: 32,
                        width: 32,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText.text('Address',
                              color: const Color(0xFFC9D2D7), fontSize: 12),
                          AppText.text(
                              '${state.destinationLocation}, ${state.destinationLocationSubAddress}',
                              fontSize: 16)
                        ],
                      ))
                    ],
                  )),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Color(0xFF415058),
                  )
                ],
              )),
          const SizedBox(height: 20),
          ListTile(
              onTap: () async {
                _textFieldController.text = dropoffContactPhoneNumber ?? '';
                final String? info =
                    await additioalDetailsBottomSheet(title: 'Phone number');

                if (info != null) {
                  setState(() {
                    dropoffContactPhoneNumber = info;
                  });
                }
              },
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                      child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/svg/phone.svg',
                        height: 32,
                        width: 32,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText.text('Phone number',
                              color: const Color(0xFFC9D2D7), fontSize: 12),
                          AppText.text(
                              dropoffContactPhoneNumber ?? 'Phone number',
                              fontSize: 16,
                              color: dropoffContactPhoneNumber != null
                                  ? Colors.white
                                  : const Color(0xFFC9D2D7))
                        ],
                      ))
                    ],
                  )),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Color(0xFF415058),
                  )
                ],
              )),
          // const SizedBox(height: 20),
          // ListTile(
          //     onTap: () async {
          //       _textFieldController.text = additonalDeliveryInformation ?? '';
          //       final String? info = await additioalDetailsBottomSheet(
          //           title: 'More information');

          //       if (info != null) {
          //         setState(() {
          //           additonalDeliveryInformation = info;
          //         });
          //       }
          //     },
          //     dense: true,
          //     contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          //     title: Row(
          //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //       children: [
          //         Expanded(
          //             child: Row(
          //           children: [
          //             SvgPicture.asset(
          //               'assets/svg/legal.svg',
          //               height: 32,
          //               width: 32,
          //             ),
          //             const SizedBox(width: 18),
          //             Expanded(
          //                 child: Column(
          //               crossAxisAlignment: CrossAxisAlignment.start,
          //               children: [
          //                 AppText.text('More information',
          //                     color: const Color(0xFFC9D2D7), fontSize: 12),
          //                 AppText.text(
          //                     additonalDeliveryInformation ??
          //                         'Add an additional information',
          //                     fontSize: 16,
          //                     color: additonalDeliveryInformation != null
          //                         ? Colors.white
          //                         : const Color(0xFFC9D2D7))
          //               ],
          //             ))
          //           ],
          //         )),
          //         const Icon(
          //           Icons.arrow_forward_ios,
          //           color: Color(0xFF415058),
          //         )
          //       ],
          //     )),
        ],
      );
    });
  }

  Widget confirmDeliveryButton() {
    return BlocBuilder<SendPackageBloc, SendPackageState>(
        builder: (context, state) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32)
            .copyWith(top: 16),
        child: AppButton.button(
            widget: Center(
                child: AppText.text('Confirm delivery',
                    fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: () {
              // context.read<SendPackageBloc>().add(const SetDeliveryStatus(
              //     deliveryStatus: DeliveryStatus.deliveryConfirmed));
              context.read<SendPackageBloc>().add(SendDeliveryRequest(
                  pickupDetails: ContactInfo.fromJson(
                      fullname: username,
                      address: state.pickupCoordinate!,
                      phoneNumber: phoneNumber,
                      moreInformation: additonalPickupInformation,
                      locality: state.pickupLocality),
                  dropoffDetails: ContactInfo.fromJson(
                      fullname: dropoffContactName,
                      phoneNumber: dropoffContactPhoneNumber,
                      address: state.desinationCoordinate!,
                      moreInformation: dropoffAdditionalInformation,
                      locality: state.destinationLocality)));
              Navigator.pop(context);
            }),
      );
    });
  }

  additioalDetailsBottomSheet({required String title, String? initialText}) {
    return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20))),
        builder: (_) {
          return Wrap(
            children: [
              Container(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height * 0.7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: AppText.text(title),
                      ),
                      const SizedBox(height: 12),
                      Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          // height: 600,
                          child: AppTextInput.input(
                              initialValue: initialText,
                              minLines: title == 'More information' ? 4 : 1,
                              maxLines: title == 'More information' ? 4 : 1,
                              keyboardType: title == 'Phone number'
                                  ? TextInputType.phone
                                  : TextInputType.text,
                              autofocus: true,
                              controller: _textFieldController)),
                      SizedBox(height: 20),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Expanded(
                                  child: AppButton.button(
                                      backgroundColor: Colors.grey[400],
                                      widget: AppText.text('Cancel',
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600),
                                      onPressed: () {
                                        Navigator.pop(context);
                                      })),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: AppButton.button(
                                      widget: AppText.text('Done',
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600),
                                      onPressed: () async {
                                        // print(_textFieldController.text);
                                        // print(state.selectedEmoji);
                                        if (_textFieldController.text.length >
                                            2) {
                                          Navigator.pop(context,
                                              _textFieldController.text);
                                          _textFieldController.text = "";
                                        } else {
                                          var cancel =
                                              BotToast.showCustomNotification(
                                                  toastBuilder: (_) {
                                            return Container(
                                              padding: const EdgeInsets.all(20),
                                              color: Colors.red,
                                              child: Row(
                                                // mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  AppText.text(
                                                      'Name is too short',
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600),
                                                ],
                                              ),
                                            );
                                          });

                                          // cancel();
                                        }
                                      })),
                            ],
                          )),
                      // if (isKeyboardVisible == true)
                      //   SizedBox(height: res.keyboardHeight),
                      const SizedBox(height: 60),
                    ],
                  ))
            ],
          );
        });
  }
}
