// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

enum CircumWebSection { home, sender, rider }

const _themeStorageKey = 'circum.web.theme';

bool readCircumWebDarkMode() =>
    html.window.localStorage[_themeStorageKey] != 'light';

void persistCircumWebDarkMode(bool darkMode) {
  html.window.localStorage[_themeStorageKey] = darkMode ? 'dark' : 'light';
}

class CircumWebShell extends StatelessWidget {
  const CircumWebShell({
    super.key,
    required this.section,
    required this.darkMode,
    required this.onToggleTheme,
    required this.child,
    this.locationLabel,
    this.headerActions,
    this.showSectionNavigation = true,
  });

  final CircumWebSection section;
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final Widget child;
  final String? locationLabel;
  final Widget? headerActions;
  final bool showSectionNavigation;

  static const _blue = Color(0xFF3B82F6);

  void _open(String path) {
    if (Uri.base.path == path) return;
    html.window.location.assign(path);
  }

  String get _sectionLabel => switch (section) {
        CircumWebSection.home => 'Home',
        CircumWebSection.sender => 'Sender',
        CircumWebSection.rider => 'Rider',
      };

  String get _profilePath => switch (section) {
        CircumWebSection.rider => '/rider?section=profile',
        _ => '/send?tab=profile',
      };

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 760;
    final background =
        darkMode ? const Color(0xFF07090F) : const Color(0xFFF5F7FB);
    final panel = darkMode ? const Color(0xF20D111C) : const Color(0xF2FFFFFF);
    final text = darkMode ? const Color(0xFFF5F7FB) : const Color(0xFF111827);
    final muted = darkMode ? const Color(0xFF9CA8B8) : const Color(0xFF64748B);
    final border = darkMode ? const Color(0x1FFFFFFF) : const Color(0x180F172A);

    return ColoredBox(
      color: background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              height: mobile ? 58 : 68,
              padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 28),
              decoration: BoxDecoration(
                color: panel,
                border: Border(bottom: BorderSide(color: border)),
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 18),
                ],
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _open('/'),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Image.asset(
                        'assets/images/circum_wordmark.png',
                        width: mobile ? 102 : 124,
                        height: 28,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  if (!mobile && showSectionNavigation) ...[
                    _ShellNavItem(
                      label: 'Home',
                      selected: section == CircumWebSection.home,
                      onTap: () => _open('/'),
                      textColor: text,
                    ),
                    _ShellNavItem(
                      label: 'Sender',
                      selected: section == CircumWebSection.sender,
                      onTap: () => _open('/send'),
                      textColor: text,
                    ),
                    _ShellNavItem(
                      label: 'Rider',
                      selected: section == CircumWebSection.rider,
                      onTap: () => _open('/rider'),
                      textColor: text,
                    ),
                  ] else if (showSectionNavigation) ...[
                    Container(width: 1, height: 22, color: border),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        locationLabel ?? _sectionLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!mobile && headerActions != null) ...[
                    Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: headerActions!,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  IconButton(
                    tooltip: darkMode
                        ? 'Use light appearance'
                        : 'Use dark appearance',
                    onPressed: onToggleTheme,
                    icon: Icon(
                      darkMode
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      color: text,
                      size: 21,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: () =>
                        _showNotifications(context, panel, text, muted),
                    icon: Icon(Icons.notifications_none_rounded,
                        color: text, size: 22),
                  ),
                  _AccountMenu(
                    textColor: text,
                    mutedColor: muted,
                    onProfile: () => _open(_profilePath),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: KeyedSubtree(
                  key: ValueKey(section),
                  child: child,
                ),
              ),
            ),
            if (mobile && showSectionNavigation)
              Container(
                height: 68,
                decoration: BoxDecoration(
                  color: panel,
                  border: Border(top: BorderSide(color: border)),
                ),
                child: Row(
                  children: [
                    _MobileNavItem(
                      icon: Icons.home_outlined,
                      label: 'Home',
                      selected: section == CircumWebSection.home,
                      onTap: () => _open('/'),
                    ),
                    _MobileNavItem(
                      icon: Icons.send_outlined,
                      label: 'Sender',
                      selected: section == CircumWebSection.sender,
                      onTap: () => _open('/send'),
                    ),
                    _MobileNavItem(
                      icon: Icons.delivery_dining_outlined,
                      label: 'Rider',
                      selected: section == CircumWebSection.rider,
                      onTap: () => _open('/rider'),
                    ),
                    _MobileNavItem(
                      icon: Icons.person_outline_rounded,
                      label: 'Profile',
                      selected: false,
                      onTap: () => _open(_profilePath),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNotifications(
    BuildContext context,
    Color panel,
    Color text,
    Color muted,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notifications',
                  style: TextStyle(
                      color: text, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(
                FirebaseAuth.instance.currentUser == null
                    ? 'Sign in to view your Circum notifications.'
                    : 'Your notifications remain available across Circum.',
                style: TextStyle(color: muted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellNavItem extends StatelessWidget {
  const _ShellNavItem(
      {required this.label,
      required this.selected,
      required this.onTap,
      required this.textColor});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: selected ? CircumWebShell._blue : textColor,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          ),
          child: Text(label,
              style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        ),
      );
}

class _MobileNavItem extends StatelessWidget {
  const _MobileNavItem(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color:
                      selected ? CircumWebShell._blue : const Color(0xFF9CA8B8),
                  size: 21),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      color: selected
                          ? CircumWebShell._blue
                          : const Color(0xFF9CA8B8),
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu(
      {required this.textColor,
      required this.mutedColor,
      required this.onProfile});
  final Color textColor;
  final Color mutedColor;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        initialData: FirebaseAuth.instance.currentUser,
        builder: (context, snapshot) {
          final user = snapshot.data;
          final identity = (user?.displayName ?? user?.email ?? '').trim();
          final initial =
              identity.isEmpty ? 'C' : identity.characters.first.toUpperCase();
          return PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (value) async {
              if (value == 'profile') onProfile();
              if (value == 'signout') await FirebaseAuth.instance.signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'profile',
                  child: Text(
                      user == null ? 'Sign in or create account' : 'Profile')),
              if (user != null)
                const PopupMenuItem(value: 'signout', child: Text('Log out')),
            ],
            child: Semantics(
              button: true,
              label: 'Account',
              child: CircleAvatar(
                radius: 17,
                backgroundColor: const Color(0x223B82F6),
                child: Text(initial,
                    style: const TextStyle(
                        color: CircumWebShell._blue,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          );
        },
      );
}
