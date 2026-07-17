import 'package:circum/app/authentication/bloc/auth_bloc.dart';
import 'package:circum/app/send_package/bloc/send_package_bloc.dart';
import 'package:circum/app/send_package/models/contact_info.dart';
import 'package:circum/helper/toast_helper.dart';
import 'package:circum/utils/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:uuid/uuid.dart';

import '../../../utils/theme/text_field.dart';
import '../../account/bloc/account_bloc.dart';
import '../../account/view/payment.dart';

class DeliveryReviewExpandedView extends StatefulWidget {
  DeliveryReviewExpandedView({Key? key}) : super(key: key);

  @override
  State<DeliveryReviewExpandedView> createState() =>
      _DeliveryReviewExpandedViewState();
}

class _DeliveryReviewExpandedViewState
    extends State<DeliveryReviewExpandedView> {
  final TextEditingController _textFieldController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();

  bool isPhoneValid = false;
  String completeNumber = '';

  String? username;
  String? phoneNumber;
  String? additonalPickupInformation;
  String? additonalDeliveryInformation;

  String? dropoffContactName;
  String? dropoffContactPhoneNumber;
  String? dropoffAdditionalInformation;

  String? email;

  @override
  void initState() {
    final AuthBloc authBloc = context.read<AuthBloc>();
    username = authBloc.state.username;
    phoneNumber = authBloc.state.phoneNumber;
    email = authBloc.state.email;
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
              onTap: () async {
                _textFieldController.text = phoneNumber ?? '';
                final String? newPhone =
                    await additioalDetailsBottomSheet(title: 'Phone number');

                if (newPhone != null) {
                  setState(() {
                    phoneNumber = newPhone;
                  });
                  // ignore: use_build_context_synchronously
                  context
                      .read<AuthBloc>()
                      .add(UpdatePhoneNumber(value: newPhone));
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
                          AppText.text(phoneNumber ?? 'Phone number',
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
            onPressed: () async {
              if (phoneNumber == null || phoneNumber!.isEmpty) {
                return ShowToast()
                    .errorToast(title: 'Please add a pick up phone number');
              }
              final requestId = const Uuid().v4();
              final payForDelivery = await showPaymentBottomSheet(context,
                  amount: state.price!,
                  phone: phoneNumber,
                  distanceKm: state.distance,
                  weightKg: state.parcelWeightKg,
                  selectedSpeed: 'standard',
                  paymentRequestId: requestId);

              if (payForDelivery == 'success') {
                final accountState = context.read<AccountBloc>().state;
                // ignore: use_build_context_synchronously
                context.read<SendPackageBloc>().add(SendDeliveryRequest(
                    requestId: requestId,
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
                        locality: state.destinationLocality),
                    paymentIntentId: accountState.paymentIntentId,
                    quoteId: accountState.quoteId,
                    paymentSessionId: accountState.paymentSessionId));
                // The wait is required to avoid a glitch effect
                await Future.delayed(const Duration(milliseconds: 300));
                // ignore: use_build_context_synchronously
                Navigator.pop(context);
              }
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
                    minHeight: MediaQuery.of(context).size.height * 0.8,
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
                          child: title == 'Phone number'
                              ? phoneInput()
                              : AppTextInput.input(
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
                                        if (title == 'Phone number') {
                                          if (isPhoneValid == true) {
                                            Navigator.pop(
                                                context, completeNumber);
                                          }
                                        } else {
                                          if (_textFieldController.text.length >
                                              2) {
                                            Navigator.pop(context,
                                                _textFieldController.text);
                                            _textFieldController.text = "";
                                          } else {
                                            await ShowToast().errorToast(
                                                title: 'Name is too short');

                                            // cancel();
                                          }
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

  Widget phoneInput() {
    const _initialCountryCode = 'GB';
    var _country =
        countries.firstWhere((element) => element.code == _initialCountryCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AppText.text('Mobile Number', color: Colors.white),
        // const SizedBox(height: 12),
        IntlPhoneField(
          style: const TextStyle(color: Colors.white, fontFamily: 'Helvetica'),
          dropdownTextStyle:
              const TextStyle(color: Colors.white, fontFamily: 'Helvetica'),
          decoration: InputDecoration(
            fillColor: AppColors.input,
            filled: true,
            labelStyle: const TextStyle(
                fontFamily: 'Helvetica',
                fontSize: 14.0,
                fontWeight: FontWeight.w500,
                color: AppColors.grey),
            // hintText: '9020020222',
            hintStyle: TextStyle(
                color: const Color(0xFF050529).withOpacity(0.25),
                fontFamily: 'Helvetica'),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(0)),
              borderSide: BorderSide(width: 1, color: AppColors.primary),
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(0)),
              borderSide: BorderSide(color: Color(0xFF050529)),
            ),
          ),
          initialCountryCode: _initialCountryCode,
          // controller: phoneCo,
          onCountryChanged: (country) {
            print(country.name);
            print('Phone Number: ${_phoneNumberController.text}');
            _country = country;
            if (_phoneNumberController.text.isNotEmpty) {
              if (_phoneNumberController.text.length -
                          country.dialCode.length -
                          1 >=
                      country.minLength &&
                  _phoneNumberController.text.length -
                          country.dialCode.length -
                          1 <=
                      country.maxLength) {
                setState(() {
                  isPhoneValid = true;
                });

                print('valid');
              } else {
                setState(() {
                  isPhoneValid = false;
                });
                print('invalid');
              }
            }
          },
          onChanged: (val) {
            // print('Changed');
            if (val.number.length >= _country.minLength &&
                val.number.length <= _country.maxLength) {
              setState(() {
                isPhoneValid = true;
              });
            } else {
              setState(() {
                isPhoneValid = false;
              });
            }

            setState(() {
              completeNumber = val.completeNumber;
            });
            // context
            //     .read<AuthBloc>()
            //     .add(PhoneNumberChanged(phoneNumber: val.completeNumber));
          },
        )
      ],
    );
  }
}
