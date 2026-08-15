import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openCircumLegalLink(
  BuildContext context, {
  required Uri uri,
}) async {
  final allowed = uri.scheme == 'https' &&
      uri.host == 'circumuk.com' &&
      (uri.path == '/terms' || uri.path == '/privacy');
  if (!allowed) return;
  final shouldOpen = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text("You're leaving CIRCUM"),
          content: const Text('This link will open outside the CIRCUM app.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;
  if (!shouldOpen) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
