import 'package:flutter/material.dart';

abstract final class SenderTypography {
  static const cinematicFontFamily = 'Montserrat';

  static TextStyle cinematicStatus({
    required double fontSize,
    Color color = Colors.white,
    double? letterSpacing,
  }) {
    return TextStyle(
      color: color,
      fontFamily: cinematicFontFamily,
      fontSize: fontSize,
      height: 1.15,
      fontWeight: FontWeight.w600,
      letterSpacing: letterSpacing ?? cinematicLetterSpacing(fontSize),
    );
  }

  static double cinematicLetterSpacing(double fontSize) =>
      (fontSize * .08).clamp(1.2, 2.0);
}

class SenderCinematicHeading extends StatelessWidget {
  final String text;
  final double fontSize;
  final TextAlign textAlign;
  final Color color;
  final int maxLines;

  const SenderCinematicHeading(
    this.text, {
    super.key,
    this.fontSize = 24,
    this.textAlign = TextAlign.start,
    this.color = Colors.white,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final scale =
            MediaQuery.textScalerOf(context).scale(fontSize) / fontSize;
        final compact = width < 340 || scale > 1.25;
        final spacing = SenderTypography.cinematicLetterSpacing(fontSize) *
            (compact ? .62 : 1);
        return Text(
          text.toUpperCase(),
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: SenderTypography.cinematicStatus(
            fontSize: fontSize,
            color: color,
            letterSpacing: spacing,
          ),
        );
      },
    );
  }
}
