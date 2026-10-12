import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

/// Every public website brand mark returns to the root in the same tab.
/// Keep this separate from contextual back actions and authentication state.
class CircumHomeLink extends StatelessWidget {
  const CircumHomeLink({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Link(
        uri: (Uri.base.scheme == 'http' || Uri.base.scheme == 'https')
            ? Uri.base.resolve('/')
            : Uri.parse('https://circumuk.com/'),
        target: LinkTarget.self,
        builder: (context, followLink) => Semantics(
          label: 'CIRCUM home',
          link: true,
          child: TextButton(
            onPressed: followLink,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
              alignment: Alignment.centerLeft,
            ),
            child: ExcludeSemantics(child: child),
          ),
        ),
      );
}
