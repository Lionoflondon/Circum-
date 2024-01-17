import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';

import '../../../utils/theme/theme.dart';

class FAQView extends StatelessWidget {
  const FAQView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary,
      appBar: AppBar(
        backgroundColor: AppColors.secondary,
        elevation: 0,
        title: AppText.text('FAQ', fontWeight: FontWeight.w600, fontSize: 16),
      ),
      body: SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText.text('What areas do you deliver to?',
                      fontWeight: FontWeight.w600, fontSize: 16),
                  const SizedBox(height: 4),
                  AppText.text(
                      'We strive to cover a wide range of locations. Enter your delivery address in the app to check if we deliver to your area.',
                      color: AppColors.textGrey),
                  const SizedBox(height: 20),
                  AppText.text('How can I track my order?',
                      fontWeight: FontWeight.w600, fontSize: 16),
                  const SizedBox(height: 4),
                  AppText.text(
                      "Once your order is confirmed, you can track its status in real-time through the app. You'll receive notifications at each stage, from preparation to delivery.",
                      color: AppColors.textGrey),
                  const SizedBox(height: 20),
                  AppText.text('What payment methods do you accept?',
                      fontWeight: FontWeight.w600, fontSize: 16),
                  const SizedBox(height: 4),
                  AppText.text(
                      'We accept various payment methods, including credit/debit cards and digital wallets. Check the app for the specific options available in your region.',
                      color: AppColors.textGrey),
                  const SizedBox(height: 20),
                  AppText.text('Is there a minimum order requirement?',
                      fontWeight: FontWeight.w600, fontSize: 16),
                  const SizedBox(height: 4),
                  AppText.text(
                      'Minimum order requirements, if any, vary by location. You can view this information during the checkout process.',
                      color: AppColors.textGrey),
                  const SizedBox(height: 20),
                  AppText.text('How are delivery fees calculated?',
                      fontWeight: FontWeight.w600, fontSize: 16),
                  const SizedBox(height: 4),
                  AppText.text(
                      'Delivery fees are calculated based on your delivery location and the distance from the pickup location. The app will display the applicable fees before you confirm your order.',
                      color: AppColors.textGrey),
                  const SizedBox(height: 20),
                  AppText.text("What if there's an issue with my order?",
                      fontWeight: FontWeight.w600, fontSize: 16),
                  const SizedBox(height: 4),
                  AppText.text(
                      "If you encounter any problems with your order, contact our customer support through the app. We'll do our best to resolve the issue promptly.",
                      color: AppColors.textGrey),
                  const SizedBox(height: 20),
                  AppText.text("How can I provide feedback?",
                      fontWeight: FontWeight.w600, fontSize: 16),
                  const SizedBox(height: 4),
                  AppText.text(
                      "We value your feedback! You can rate your experience and leave comments within the app. Additionally, you can reach out to our customer support for any specific concerns or suggestions.",
                      color: AppColors.textGrey),
                ],
              ))),
    );
  }
}
