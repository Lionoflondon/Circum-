import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum SenderExternalDestination { terms, privacy, approvedStripePayment }

class SenderExternalNavigation {
  static final Uri termsUri = Uri.parse('https://circumuk.com/terms');
  static final Uri privacyUri = Uri.parse('https://circumuk.com/privacy');

  static bool isAllowed(
    Uri uri, {
    required SenderExternalDestination destination,
  }) {
    switch (destination) {
      case SenderExternalDestination.terms:
        return uri == termsUri;
      case SenderExternalDestination.privacy:
        return uri == privacyUri;
      case SenderExternalDestination.approvedStripePayment:
        return uri.scheme == 'https' &&
            (uri.host == 'checkout.stripe.com' ||
                uri.host.endsWith('.stripe.com'));
    }
  }

  static Future<bool> open(
    BuildContext context,
    Uri uri, {
    required SenderExternalDestination destination,
    LaunchMode mode = LaunchMode.platformDefault,
    String? webOnlyWindowName,
  }) async {
    if (!isAllowed(uri, destination: destination)) return false;

    final needsWarning =
        destination != SenderExternalDestination.approvedStripePayment;
    if (needsWarning) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("You're leaving CIRCUM"),
              content: const Text(
                'This link will open outside the CIRCUM app.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return false;
    }

    return launchUrl(uri, mode: mode, webOnlyWindowName: webOnlyWindowName);
  }
}
