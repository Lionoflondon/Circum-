import 'package:flutter/material.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../../../../utils/theme/text_field.dart';
import '../../../../utils/theme/theme.dart';

showEditBottomSheet(context, {String? val, required String title}) {
  return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      backgroundColor: AppColors.secondary,
      builder: (context) {
        return ButtSheet(
          title: title,
          val: val,
        );
      });
}

class ButtSheet extends StatefulWidget {
  final String? val;
  final String title;
  const ButtSheet({super.key, this.val, required this.title});
  @override
  ButtSheetState createState() => ButtSheetState();
}

class ButtSheetState extends State<ButtSheet> {
  final TextEditingController _textFieldController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();

  bool isPhoneValid = false;
  String completeNumber = '';

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    _textFieldController.text = widget.val ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
        padding: MediaQuery.of(context).viewInsets,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(context).size.height),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.close, color: Colors.white),
                    )
                  ],
                ),
                Row(children: [
                  AppText.text(widget.title,
                      fontWeight: FontWeight.w600, fontSize: 16)
                ]),
                const SizedBox(height: 12),
                widget.title == 'Phone number'
                    ? phoneInput()
                    : AppTextInput.input(controller: _textFieldController),
                const SizedBox(height: 80),
                AppButton.button(
                    widget: Center(
                        child: AppText.text('Update details',
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    onPressed: () {
                      if (widget.title == 'Phone number') {
                        if (isPhoneValid == true) {
                          Navigator.pop(context, completeNumber);
                        }
                      } else {
                        if (_textFieldController.text.trim() != '') {
                          Navigator.pop(context, _textFieldController.text);
                        }
                      }
                      // print(_textFieldController.text);
                    })
              ],
            )));
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
