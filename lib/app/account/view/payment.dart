import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:circum/helper/toast_helper.dart';
import 'package:circum/utils/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../authentication/bloc/auth_bloc.dart';
import '../bloc/account_bloc.dart';

showPaymentBottomSheet(context, {required double amount, String? phone}) {
  return showModalBottomSheet(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      enableDrag: false,
      constraints: BoxConstraints(
        maxHeight: 300,
        minWidth: MediaQuery.of(context).size.width,
      ),
      backgroundColor: Colors.transparent,
      builder: (context) {
        return PaymentScreen(
          amount: amount,
          phone: phone,
        );
      });
}

class PaymentScreen extends StatefulWidget {
  final double amount;
  final String? phone;
  const PaymentScreen({Key? key, required this.amount, this.phone})
      : super(key: key);

  @override
  PaymentScreenState createState() => PaymentScreenState();
}

class PaymentScreenState extends State<PaymentScreen> {
  String? email;
  @override
  void initState() {
    final AuthBloc authBloc = context.read<AuthBloc>();
    email = authBloc.state.email;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.secondary,
        body: BlocListener<AccountBloc, AccountState>(
          listener: ((context, state) async {
            if (state.status == PaymentStatus.loading) {
              // isDismissible = false;
            }

            if (state.status == PaymentStatus.failure) {
              // isDismissible = true;
            }

            if (state.status == PaymentStatus.success) {
              // isDismissible = true;
              context.read<AccountBloc>().add(PaymentStart());

              ShowToast().successToast(title: 'Payment successful');

              return Navigator.pop(context, 'success');
            }
          }),
          child: BlocBuilder<AccountBloc, AccountState>(
            builder: (context, state) {
              CardEditController controller = CardEditController(
                initialDetails: state.cardFieldInputDetails,
              );
              if (state.status == PaymentStatus.initial) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20).copyWith(top: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          AppText.text('Pay £${widget.amount}',
                              fontWeight: FontWeight.w600,
                              fontSize: 20,
                              color: Colors.white),
                          IconButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              icon: const Icon(
                                Icons.close,
                                color: AppColors.primary,
                              ))
                        ],
                      ),
                      const SizedBox(height: 20),
                      // CardField(
                      //   cursorColor: Colors.white,
                      //   onCardChanged: (details) {
                      //     // context
                      //     // .read<AddPaymentMethodCubit>()
                      //     // .onDetailsChanged(details),
                      //     // print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
                      //     // print(details);
                      //   },
                      //   decoration: const InputDecoration(
                      //     focusedBorder: UnderlineInputBorder(
                      //       borderSide:
                      //           BorderSide(color: AppColors.primary, width: 2),
                      //     ),
                      //   ),
                      //   controller: controller,
                      //   autofocus: true,
                      //   // style: CardFormStyle(
                      //   //   cursorColor: AppColors.primary,
                      //   //   // backgroundColor: AppColors.secondary,
                      //   //   textColor: Colors.white,
                      //   //   placeholderColor: Colors.white,
                      //   // )
                      // ),
                      // const SizedBox(height: 4),
                      // Row(
                      //   children: [
                      //     Checkbox(
                      //         value: state.saveCard,
                      //         activeColor: AppColors.primary,
                      //         onChanged: (val) {
                      //           context
                      //               .read<AccountBloc>()
                      //               .add(SaveCard(val: !state.saveCard));
                      //         }),
                      //     Expanded(
                      //         child: GestureDetector(
                      //             onTap: () {
                      //               context
                      //                   .read<AccountBloc>()
                      //                   .add(SaveCard(val: !state.saveCard));
                      //             },
                      //             child: AppText.text(
                      //                 'Save this card for later use.',
                      //                 color: MediaQuery.of(context)
                      //                             .platformBrightness ==
                      //                         Brightness.light
                      //                     ? Colors.black
                      //                     : Colors.white)))
                      //   ],
                      // ),
                      // const SizedBox(height: 10),
                      AppButton.button(
                          onPressed: () {
                            context.read<AccountBloc>().add(
                                  PaymentCreateIntent(
                                    // billingDetails: BillingDetails(
                                    //   phone: widget.phone,
                                    // ),
                                    amount: (widget.amount * 100).round(),
                                    email: email!,
                                    saveCard: state.saveCard,
                                  ),
                                );
                            // print(controller.details.complete);
                            // (controller.details.complete)
                            //     ? context.read<AccountBloc>().add(
                            //           PaymentCreateIntent(
                            //             billingDetails: BillingDetails(
                            //               phone: widget.phone,
                            //             ),
                            //             amount: (widget.amount * 100).round(),
                            //             email: email!,
                            //             saveCard: state.saveCard,
                            //           ),
                            //         )
                            //     : ScaffoldMessenger.of(context).showSnackBar(
                            //         const SnackBar(
                            //           content:
                            //               Text('The form is not complete.'),
                            //         ),
                            //       );
                          },
                          widget: AppText.text('Pay',
                              fontWeight: FontWeight.w600, fontSize: 16))
                    ],
                  ),
                );
              }
              if (state.status == PaymentStatus.success) {
                return PopScope(
                    onPopInvoked: (val) => false,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppText.text('The payment is successful.',
                            color: Colors.white, fontWeight: FontWeight.w600),
                        const SizedBox(
                          height: 10,
                          width: double.infinity,
                        ),
                        AppButton.button(
                          onPressed: () {
                            context.read<AccountBloc>().add(PaymentStart());
                          },
                          widget: AppText.text('Proceed'),
                        ),
                      ],
                    ));
              }
              if (state.status == PaymentStatus.failure) {
                return Column(
                  // mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AppText.text('Pay £${widget.amount}',
                            fontWeight: FontWeight.w600,
                            fontSize: 20,
                            color: MediaQuery.of(context).platformBrightness ==
                                    Brightness.light
                                ? Colors.black
                                : Colors.white),
                        IconButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            icon: const Icon(
                              Icons.close,
                              color: AppColors.primary,
                            ))
                      ],
                    ),
                    Expanded(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          AppText.text('The payment failed.',
                              color: Colors.white, fontWeight: FontWeight.w600),
                          const SizedBox(
                            height: 16,
                            width: double.infinity,
                          ),
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: AppButton.button(
                                  onPressed: () {
                                    context.read<AccountBloc>().add(
                                          PaymentCreateIntent(
                                            amount:
                                                (widget.amount * 100).round(),
                                            email: email!,
                                            saveCard: state.saveCard,
                                          ),
                                        );
                                  },
                                  widget: Center(
                                      child: AppText.text('Try again',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16))))
                          // ElevatedButton(
                          //   style: TextButton.styleFrom(
                          //       backgroundColor: AppColors.primary),
                          //   onPressed: () {
                          //     context.read<AccountBloc>().add(PaymentStart());
                          //   },
                          //   child: AppText.text('Try again'),
                          // ),
                        ]))
                  ],
                );
              }

              return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AppText.text('Processing...',
                        color: Colors.white, fontWeight: FontWeight.w600),
                    const SizedBox(height: 12),
                    const Center(
                        child: CircularProgressIndicator(
                      color: AppColors.primary,
                    ))
                  ]);
            },
          ),
        ));
  }
}
