import 'package:flutter/material.dart';

import '../../../../utils/theme/text_field.dart';
import '../../../../utils/theme/theme.dart';

showImageBottomSheet(context) {
  return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      backgroundColor: AppColors.secondary,
      builder: (context) {
        return ImageButtSheet();
      });
}

class ImageButtSheet extends StatefulWidget {
  const ImageButtSheet({super.key});
  @override
  ImageButtSheetState createState() => ImageButtSheetState();
}

class ImageButtSheetState extends State<ImageButtSheet> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
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
                  AppText.text('Update profile photo from',
                      fontWeight: FontWeight.w600, fontSize: 16)
                ]),
                const SizedBox(height: 12),
                AppButton.button(
                    backgroundColor: AppColors.input,
                    widget: Center(
                        child: AppText.text('Camera',
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    onPressed: () {
                      Navigator.pop(context, 'camera');
                      // print(_textFieldController.text);
                    }),
                const SizedBox(height: 12),
                AppButton.button(
                    backgroundColor: AppColors.input,
                    widget: Center(
                        child: AppText.text('Photo library',
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    onPressed: () {
                      Navigator.pop(context, 'library');
                      // print(_textFieldController.text);
                    }),
                const SizedBox(height: 20),
              ],
            )));
  }
}
