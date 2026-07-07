import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum SenderGiftsIconKind { gift, self, mask, people }

class SenderGiftsIcon extends StatelessWidget {
  final double size;
  final SenderGiftsIconKind kind;

  const SenderGiftsIcon({
    super.key,
    this.size = 44,
    this.kind = SenderGiftsIconKind.gift,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .36),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _GiftIconTokens.iri1,
            _GiftIconTokens.iri2,
            _GiftIconTokens.iri3,
            _GiftIconTokens.iri4,
            _GiftIconTokens.iri5,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _GiftIconTokens.iri2.withValues(alpha: .18),
            blurRadius: size * .45,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: SvgPicture.string(
        _GiftIcons.byKind(kind),
        width: size * .5,
        height: size * .5,
        colorFilter: const ColorFilter.mode(
          _GiftIconTokens.ink,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

class _GiftIcons {
  static const gift =
      '<svg width="22" height="22" viewBox="0 0 24 24" fill="none"><rect x="3" y="9" width="18" height="11" rx="1.5" stroke="currentColor" stroke-width="1.7"/><path d="M3 9h18M12 9v11M12 9c-2-4-7-4-7-1s3 1 7 1zm0 0c2-4 7-4 7-1s-3 1-7 1z" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/></svg>';
  static const self =
      '<svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="8" r="4" stroke="currentColor" stroke-width="1.7"/><path d="M4 20c0-4 4-6 8-6s8 2 8 6" stroke="currentColor" stroke-width="1.7"/></svg>';
  static const mask =
      '<svg width="22" height="22" viewBox="0 0 24 24" fill="none"><path d="M4 10c0-3 3.5-6 8-6s8 3 8 6-2 8-8 8-8-5-8-8z" stroke="currentColor" stroke-width="1.7"/><circle cx="9" cy="10" r="1.2" fill="currentColor"/><circle cx="15" cy="10" r="1.2" fill="currentColor"/></svg>';
  static const people =
      '<svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="8" cy="8" r="3" stroke="currentColor" stroke-width="1.7"/><circle cx="17" cy="9" r="2.6" stroke="currentColor" stroke-width="1.7"/><path d="M2 20c0-3.5 3-5.5 6-5.5s6 2 6 5.5M14 20c0-2.6 2-4.5 5-4.5s5 1.9 5 4.5" stroke="currentColor" stroke-width="1.7"/></svg>';

  static String byKind(SenderGiftsIconKind kind) {
    switch (kind) {
      case SenderGiftsIconKind.gift:
        return gift;
      case SenderGiftsIconKind.self:
        return self;
      case SenderGiftsIconKind.mask:
        return mask;
      case SenderGiftsIconKind.people:
        return people;
    }
  }
}

class _GiftIconTokens {
  static const iri1 = Color(0xFFA8EDEA);
  static const iri2 = Color(0xFFC9B8FF);
  static const iri3 = Color(0xFFFFD6E8);
  static const iri4 = Color(0xFFB8F0D8);
  static const iri5 = Color(0xFFD4C5FF);
  static const ink = Color(0xFF1A1330);
}
