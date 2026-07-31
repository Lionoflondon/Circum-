import 'package:flutter/material.dart';

import 'sender_ui_baseline.dart';

typedef SenderPagePaddingBuilder = EdgeInsets Function(BoxConstraints);

EdgeInsets senderPrimaryPagePadding(
  BoxConstraints constraints, {
  double mobileHorizontal = SenderUiBaseline.pageHorizontal,
  double desktopHorizontal = SenderUiBaseline.pageHorizontal,
  double mobileTop = SenderUiBaseline.pageTop,
  double desktopTop = SenderUiBaseline.pageTop,
  double bottom = SenderUiBaseline.pageBottom,
}) {
  final wide = constraints.maxWidth >= 720;
  return EdgeInsets.fromLTRB(
    wide ? desktopHorizontal : mobileHorizontal,
    wide ? desktopTop : mobileTop,
    wide ? desktopHorizontal : mobileHorizontal,
    bottom,
  );
}

class SenderPrimaryPageShell extends StatelessWidget {
  static const maxContentWidth = 1280.0;

  final Widget child;
  final Decoration? decoration;
  final SenderPagePaddingBuilder? paddingBuilder;
  final double maxWidth;

  const SenderPrimaryPageShell({
    super.key,
    required this.child,
    this.decoration,
    this.paddingBuilder,
    this.maxWidth = maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: decoration ?? const BoxDecoration(),
      child: SizedBox.expand(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = paddingBuilder?.call(constraints) ??
                senderPrimaryPagePadding(constraints);
            final contentWidth =
                (constraints.maxWidth - padding.horizontal)
                    .clamp(0.0, double.infinity);
            final contentHeight = (constraints.maxHeight - padding.vertical)
                .clamp(0.0, double.infinity);
            return Padding(
              padding: padding,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidth,
                  height: contentHeight,
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SenderScrollablePageShell extends StatelessWidget {
  final List<Widget> children;
  final Decoration? decoration;
  final SenderPagePaddingBuilder? paddingBuilder;
  final double maxWidth;
  final Key? scrollKey;

  const SenderScrollablePageShell({
    super.key,
    required this.children,
    this.decoration,
    this.paddingBuilder,
    this.maxWidth = SenderPrimaryPageShell.maxContentWidth,
    this.scrollKey,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: decoration ?? const BoxDecoration(),
      child: SizedBox.expand(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = paddingBuilder?.call(constraints) ??
                senderPrimaryPagePadding(constraints);
            final contentWidth =
                (constraints.maxWidth - padding.horizontal)
                    .clamp(0.0, double.infinity);
            final contentHeight = (constraints.maxHeight - padding.vertical)
                .clamp(0.0, double.infinity);
            return Padding(
              padding: padding,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidth,
                  height: contentHeight,
                  child: ListView(
                    key: scrollKey,
                    padding: EdgeInsets.zero,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
