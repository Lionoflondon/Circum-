import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Every public website brand mark returns to the root in the same tab.
/// Keep this separate from contextual back actions and authentication state.
class CircumHomeLink extends StatelessWidget {
  const CircumHomeLink({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final home = (Uri.base.scheme == 'http' || Uri.base.scheme == 'https')
        ? Uri.base.resolve('/')
        : Uri.parse('https://circumuk.com/');
    void openHome() {
      launchUrl(home, webOnlyWindowName: '_self');
    }

    return Semantics(
      label: 'CIRCUM home',
      link: true,
      onTap: openHome,
      excludeSemantics: true,
      child: TextButton(
        onPressed: openHome,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          alignment: Alignment.centerLeft,
        ),
        child: child,
      ),
    );
  }
}
