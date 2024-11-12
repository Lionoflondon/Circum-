import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';

import '../utils/theme/theme.dart';

class ShowToast {
  errorToast({required String title, String? description}) {
    BotToast.showCustomNotification(
        duration: const Duration(seconds: 5),
        toastBuilder: (_) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: const Color(0xFFFBE6D7),
                border: Border.all(
                    color: const Color.fromARGB(255, 207, 87, 65), width: 2)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.cancel_outlined,
                  color: Colors.black,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText.text(title,
                        color: Colors.black, fontWeight: FontWeight.w700),
                    if (description != null)
                      AppText.text(
                        description,
                        color: Colors.black.withOpacity(0.8),
                      ),
                  ],
                )),
                const Opacity(
                  opacity: 0,
                  child: Icon(
                    Icons.cancel_outlined,
                    color: Colors.black,
                    size: 20,
                  ),
                )
              ],
            ),
          );
        });
  }

  infoToast({required String title, String? description}) {
    BotToast.showCustomNotification(
        duration: const Duration(seconds: 5),
        toastBuilder: (_) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: const Color(0xFFE0F6FE),
                border: Border.all(color: const Color(0xFFA7D1F9), width: 2)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Colors.black,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText.text(title,
                        color: Colors.black, fontWeight: FontWeight.w700),
                    if (description != null)
                      AppText.text(
                        description,
                        color: Colors.black.withOpacity(0.8),
                      ),
                  ],
                )),
                const Opacity(
                  opacity: 0,
                  child: Icon(
                    Icons.info_outline,
                    color: Colors.black,
                    size: 20,
                  ),
                )
              ],
            ),
          );
        });
  }

  successToast({required String title, String? description}) {
    BotToast.showCustomNotification(
        duration: const Duration(seconds: 5),
        toastBuilder: (_) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: const Color(0xFFE8FAD9),
                border: Border.all(color: const Color(0xFFB0DF9D), width: 2)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.black,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText.text(title,
                        color: Colors.black, fontWeight: FontWeight.w700),
                    if (description != null)
                      AppText.text(
                        description,
                        color: Colors.black.withOpacity(0.8),
                      ),
                  ],
                )),
                const Opacity(
                  opacity: 0,
                  child: Icon(
                    Icons.check_circle_outline,
                    color: Colors.black,
                    size: 20,
                  ),
                )
              ],
            ),
          );
        });
  }
}
