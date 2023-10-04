import 'package:circum/utils/theme/text_field.dart';
import 'package:flutter/material.dart';

import '../../../../utils/theme/theme.dart';

showEditFirstNameSheet(context) {
  return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      backgroundColor: AppColors.secondary,
      builder: (context) {
        return ButtShit();
      });
}

class ButtShit extends StatelessWidget {
  const ButtShit({super.key});

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
                  AppText.text('First name',
                      fontWeight: FontWeight.w600, fontSize: 16)
                ]),
                const SizedBox(height: 12),
                AppTextInput.input(),
                const SizedBox(height: 100),
                AppButton.button(
                    widget: Center(
                        child: AppText.text('Update details',
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    onPressed: () {})
              ],
            )));
  }
}
