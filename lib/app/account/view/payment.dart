import 'package:bot_toast/bot_toast.dart';
import 'package:circum/utils/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../bloc/account_bloc.dart';

showPaymentBottomSheet(context, {required int amount}) {
  return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      backgroundColor: AppColors.secondary,
      builder: (context) {
        return PaymentScreen(
          amount: amount,
        );
      });
}

class PaymentScreen extends StatelessWidget {
  final int amount;
  const PaymentScreen({Key? key, required this.amount}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocListener<AccountBloc, AccountState>(
        listener: ((context, state) {
          if (state.status == PaymentStatus.success) {
            context.read<AccountBloc>().add(PaymentStart());
            BotToast.showCustomNotification(
                duration: const Duration(seconds: 8),
                toastBuilder: (_) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    margin: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Color.fromARGB(255, 50, 152, 53),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 4),
                        AppText.text('Payment Successful',
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ],
                    ),
                  );
                });
            return Navigator.pop(context, 'success');
          }
        }),
        child: Scaffold(
          backgroundColor: AppColors.secondary,
          body: BlocBuilder<AccountBloc, AccountState>(
            builder: (context, state) {
              CardFormEditController controller = CardFormEditController(
                initialDetails: state.cardFieldInputDetails,
              );

              if (state.status == PaymentStatus.initial) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppText.text('Payment',
                          fontWeight: FontWeight.w600, fontSize: 20),
                      const SizedBox(height: 20),
                      CardFormField(
                          controller: controller,
                          autofocus: true,
                          countryCode: "NG",
                          style: CardFormStyle(
                            backgroundColor: AppColors.secondary,
                            textColor: Colors.white,
                          )),
                      const SizedBox(height: 10),
                      AppButton.button(
                          onPressed: () {
                            (controller.details.complete)
                                ? context.read<AccountBloc>().add(
                                      PaymentCreateIntent(
                                          billingDetails: const BillingDetails(
                                            email: 'alejimoses@gmail.com',
                                          ),
                                          amount: amount),
                                    )
                                : ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('The form is not complete.'),
                                    ),
                                  );
                          },
                          widget: AppText.text('Pay',
                              fontWeight: FontWeight.w600, fontSize: 16))
                    ],
                  ),
                );
              }
              if (state.status == PaymentStatus.success) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppText.text('The payment is successful.'),
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
                );
              }
              if (state.status == PaymentStatus.failure) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('The payment failed.'),
                    const SizedBox(
                      height: 10,
                      width: double.infinity,
                    ),
                    ElevatedButton(
                      onPressed: () {
                        context.read<AccountBloc>().add(PaymentStart());
                      },
                      child: const Text('Try again'),
                    ),
                  ],
                );
              }

              return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AppText.text('Procressing payment'),
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
