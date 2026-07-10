import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';

class AppGlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? accent;
  final Color? surfaceColor;
  final Color? borderColor;
  final bool highContrast;
  final BoxConstraints? constraints;
  final VoidCallback? onTap;

  const AppGlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTokens.space16),
    this.radius = AppTokens.radius24,
    this.accent,
    this.surfaceColor,
    this.borderColor,
    this.highContrast = false,
    this.constraints,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedBorderColor = borderColor ??
        (highContrast ? AppTokens.strongGlassBorder : AppTokens.glassBorder);
    final body = Container(
      constraints: constraints,
      padding: padding,
      decoration: BoxDecoration(
        color: surfaceColor ??
            (highContrast ? AppTokens.strongGlass : AppTokens.glass),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: resolvedBorderColor,
          width: highContrast ? 1.3 : 1,
        ),
        boxShadow: [
          AppTokens.cardShadow,
          if (accent != null)
            BoxShadow(
              color: accent!.withValues(alpha: highContrast ? .22 : .10),
              blurRadius: highContrast ? 32 : 26,
              offset: const Offset(0, 14),
            ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: onTap == null
            ? body
            : Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(radius),
                  child: body,
                ),
              ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accent;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTokens.space16),
    this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) => AppGlassContainer(
        padding: padding,
        accent: accent,
        onTap: onTap,
        child: child,
      );
}

enum AppButtonStyle { primary, secondary, quiet }

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonStyle style;
  final bool expanded;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = AppButtonStyle.primary,
    this.expanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label)
            ],
          );
    final button = switch (style) {
      AppButtonStyle.primary =>
        FilledButton(onPressed: onPressed, child: child),
      AppButtonStyle.secondary =>
        OutlinedButton(onPressed: onPressed, child: child),
      AppButtonStyle.quiet => TextButton(onPressed: onPressed, child: child),
    };
    return SizedBox(
      width: expanded ? double.infinity : null,
      height: 52,
      child: button,
    );
  }
}

class AppToggle extends StatelessWidget {
  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;

  const AppToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        secondary: icon == null ? null : Icon(icon),
        title: Text(label),
        subtitle: detail == null ? null : Text(detail!),
      );
}

class AppSection extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  const AppSection({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.dmSerifDisplay(
                    color: AppTokens.text,
                    fontSize: 22,
                  ),
                ),
              ),
              if (actionLabel != null)
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
          const SizedBox(height: AppTokens.space12),
          child,
        ],
      );
}

class AppListTile extends StatelessWidget {
  final String title;
  final String? detail;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;

  const AppListTile({
    super.key,
    required this.title,
    required this.icon,
    this.detail,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        minVerticalPadding: AppTokens.space8,
        leading: Icon(icon, color: AppTokens.primaryLight),
        title: Text(title),
        subtitle: detail == null ? null : Text(detail!),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}

class AppAvatar extends StatelessWidget {
  final String? imageUrl;
  final String label;
  final double size;

  const AppAvatar({
    super.key,
    required this.label,
    this.imageUrl,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isEmpty ? 'C' : label.trim()[0].toUpperCase();
    return Semantics(
      label: '$label avatar',
      image: true,
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: AppTokens.raisedPanel,
        foregroundImage: imageUrl == null || imageUrl!.isEmpty
            ? null
            : NetworkImage(imageUrl!),
        child: Text(initial, style: TextStyle(fontSize: size * .38)),
      ),
    );
  }
}

enum AppStatusTone { info, success, warning, danger, muted }

class AppStatusBadge extends StatelessWidget {
  final String label;
  final AppStatusTone tone;
  final Color? color;
  final bool highContrast;

  const AppStatusBadge({
    super.key,
    required this.label,
    this.tone = AppStatusTone.info,
    this.color,
    this.highContrast = false,
  });

  Color get _color =>
      color ??
      switch (tone) {
        AppStatusTone.success => AppTokens.success,
        AppStatusTone.warning => AppTokens.warning,
        AppStatusTone.danger => AppTokens.danger,
        AppStatusTone.muted => AppTokens.mutedText,
        AppStatusTone.info => AppTokens.primaryLight,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: highContrast ? .22 : .12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _color.withValues(alpha: highContrast ? .84 : .32),
            width: highContrast ? 1.3 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: highContrast ? Colors.white : _color,
            fontSize: 11,
            fontWeight: highContrast ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      );
}

class AppRankBadge extends StatelessWidget {
  final String rank;
  const AppRankBadge({super.key, required this.rank});

  Color get _color => switch (rank.trim().toLowerCase()) {
        'agent' => const Color(0xFFC7D2E0),
        'sentinel' => AppTokens.primaryLight,
        'warden' => const Color(0xFF34D399),
        'knight' => const Color(0xFFC4B5FD),
        'veteran' => const Color(0xFFFCD34D),
        _ => AppTokens.mutedText,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _color.withValues(alpha: .28)),
        ),
        child: Text(
          rank,
          style: TextStyle(
              color: _color, fontWeight: FontWeight.w700, fontSize: 11),
        ),
      );
}

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppTokens.primaryLight),
            const SizedBox(height: AppTokens.space16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppTokens.space8),
            Text(body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            if (actionLabel != null) ...[
              const SizedBox(height: AppTokens.space20),
              AppButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      );
}

class AppTimeline extends StatelessWidget {
  final List<Widget> children;
  final Color color;

  const AppTimeline(
      {super.key, required this.children, this.color = AppTokens.primaryLight});

  @override
  Widget build(BuildContext context) => Column(
        children: List.generate(children.length, (index) {
          final last = index == children.length - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 18,
                  child: Column(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration:
                            BoxDecoration(shape: BoxShape.circle, color: color),
                      ),
                      if (!last)
                        Expanded(
                            child: Container(
                                width: 1, color: color.withValues(alpha: .24))),
                    ],
                  ),
                ),
                const SizedBox(width: AppTokens.space8),
                Expanded(
                    child: Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppTokens.space12),
                        child: children[index])),
              ],
            ),
          );
        }),
      );
}
