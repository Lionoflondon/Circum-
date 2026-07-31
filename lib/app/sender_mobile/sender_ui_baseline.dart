import 'package:flutter/material.dart';

/// Sender UI Baseline v1.0 is the approved visual contract for the Sender app.
///
/// Visual changes to the primary tabs, shell, navigation, spacing, glass
/// language, or responsive behavior must intentionally bump [version] and pass
/// the Sender UI baseline tests.
class SenderUiBaseline {
  static const version = 'Sender UI Baseline v1.0';

  const SenderUiBaseline._();

  static const pageHorizontal = 20.0;
  static const pageTop = 18.0;
  static const pageBottom = 0.0;
  static const navSafeAreaMinimum = EdgeInsets.fromLTRB(10, 5, 10, 7);
  static const navItemMargin = EdgeInsets.symmetric(horizontal: 2);
  static const navItemPadding = EdgeInsets.symmetric(vertical: 8);
  static const navIconLabelGap = 4.0;
  static const navLabelSize = 11.0;
  static const navItemRadius = 18.0;
  static const motionFast = Duration(milliseconds: 120);
  static const motionStandard = Duration(milliseconds: 220);

  static const breakpoints = SenderUiBreakpoints();
  static const spacing = SenderUiSpacing();
  static const radius = SenderUiRadius();
  static const shadows = SenderUiShadows();
  static const blur = SenderUiBlur();
  static const motion = SenderUiMotion();
  static const navigation = SenderUiNavigation();
  static const typography = SenderUiTypography();
  static const icons = SenderUiIcons();
  static const shell = SenderUiShell();
  static const colors = SenderUiColors();
}

class SenderUiBreakpoints {
  final double phoneMax;
  final double tabletMin;
  final double desktopMin;
  final double largeDesktopMin;

  const SenderUiBreakpoints({
    this.phoneMax = 599,
    this.tabletMin = 600,
    this.desktopMin = 1024,
    this.largeDesktopMin = 1440,
  });
}

class SenderUiSpacing {
  final double pageHorizontal;
  final double pageTop;
  final double pageBottom;
  final double cardGap;
  final double sectionGap;

  const SenderUiSpacing({
    this.pageHorizontal = SenderUiBaseline.pageHorizontal,
    this.pageTop = SenderUiBaseline.pageTop,
    this.pageBottom = SenderUiBaseline.pageBottom,
    this.cardGap = 12,
    this.sectionGap = 28,
  });
}

class SenderUiRadius {
  final double navItem;
  final double card;
  final double panel;
  final double pill;

  const SenderUiRadius({
    this.navItem = SenderUiBaseline.navItemRadius,
    this.card = 24,
    this.panel = 28,
    this.pill = 999,
  });
}

class SenderUiShadows {
  final double navBlur;
  final Offset navOffset;
  final double selectedNavBlur;

  const SenderUiShadows({
    this.navBlur = 30,
    this.navOffset = const Offset(0, -12),
    this.selectedNavBlur = 20,
  });
}

class SenderUiBlur {
  final double glass;

  const SenderUiBlur({this.glass = 20});
}

class SenderUiMotion {
  final Duration fast;
  final Duration standard;
  final Curve curve;

  const SenderUiMotion({
    this.fast = SenderUiBaseline.motionFast,
    this.standard = SenderUiBaseline.motionStandard,
    this.curve = Curves.easeOutCubic,
  });
}

class SenderUiNavigation {
  final EdgeInsets safeAreaMinimum;
  final EdgeInsets itemMargin;
  final EdgeInsets itemPadding;
  final double iconLabelGap;
  final double labelSize;

  const SenderUiNavigation({
    this.safeAreaMinimum = SenderUiBaseline.navSafeAreaMinimum,
    this.itemMargin = SenderUiBaseline.navItemMargin,
    this.itemPadding = SenderUiBaseline.navItemPadding,
    this.iconLabelGap = SenderUiBaseline.navIconLabelGap,
    this.labelSize = SenderUiBaseline.navLabelSize,
  });
}

class SenderUiTypography {
  final double profileTitle;
  final double navLabel;

  const SenderUiTypography({
    this.profileTitle = 30,
    this.navLabel = SenderUiBaseline.navLabelSize,
  });
}

class SenderUiIcons {
  final double defaultSize;

  const SenderUiIcons({this.defaultSize = 24});
}

class SenderUiShell {
  final bool allowNestedTabScaffold;
  final bool allowNavigationScaling;
  final bool allowPageWidthCap;

  const SenderUiShell({
    this.allowNestedTabScaffold = false,
    this.allowNavigationScaling = false,
    this.allowPageWidthCap = false,
  });
}

class SenderUiColors {
  final Color background;
  final Color navigationBackground;
  final Color navigationBorder;
  final Color senderBlue;
  final Color senderLightBlue;
  final Color muted;

  const SenderUiColors({
    this.background = const Color(0xFF07090F),
    this.navigationBackground = const Color(0xF20A1020),
    this.navigationBorder = const Color(0x29FFFFFF),
    this.senderBlue = const Color(0xFF3B82F6),
    this.senderLightBlue = const Color(0xFF60A5FA),
    this.muted = const Color(0xFF9CA3AF),
  });
}
