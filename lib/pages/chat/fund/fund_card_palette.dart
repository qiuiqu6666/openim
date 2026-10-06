import 'package:flutter/painting.dart';
import 'package:openim_common/openim_common.dart';

/// Exact palettes and opened-tone transformation from the 99chat fund cards.
class FundCardPalette {
  const FundCardPalette({
    required this.body,
    required this.bodyHighlight,
    required this.footer,
    required this.iconBg,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.footerText,
  });

  final Color body;
  final Color bodyHighlight;
  final Color footer;
  final Color iconBg;
  final Color icon;
  final Color title;
  final Color subtitle;
  final Color meta;
  final Color footerText;

  static const packet = FundCardPalette(
    body: Color(0xFFF55E44),
    bodyHighlight: Color(0xFFFA6A4E),
    footer: Color(0xFFE8553C),
    iconBg: Color(0xFFFFF4E8),
    icon: Color(0xFFF55E44),
    title: Color(0xFFFFFBF5),
    subtitle: Color(0xFFFFE8C4),
    meta: Color(0xFFFFDDB8),
    footerText: Color(0xFFFFD4B0),
  );

  static const transfer = FundCardPalette(
    body: Color(0xFFD47166),
    bodyHighlight: Color(0xFFD47166),
    footer: Color(0xFFC06258),
    iconBg: Color(0xFFFFF1EE),
    icon: Color(0xFFA85A52),
    title: Color(0xFFFFF9F7),
    subtitle: Color(0xFFFFECE8),
    meta: Color(0xFFFFECE8),
    footerText: Color(0xFFFFDED8),
  );

  FundCardPalette opened() => FundCardPalette(
        body: _openedTone(body, towardWhite: .34, saturation: .72),
        bodyHighlight:
            _openedTone(bodyHighlight, towardWhite: .40, saturation: .76),
        footer: _openedTone(footer, towardWhite: .30, saturation: .70),
        iconBg: _openedTone(iconBg, towardWhite: .22, saturation: .85),
        icon: icon,
        title: _openedTone(title, towardWhite: .10, saturation: .92),
        subtitle: _openedTone(subtitle, towardWhite: .18, saturation: .80),
        meta: _openedTone(meta, towardWhite: .20, saturation: .78),
        footerText: _openedTone(footerText, towardWhite: .24, saturation: .75),
      );

  static Color _openedTone(Color color,
      {required double towardWhite, required double saturation}) {
    final lightened =
        Color.lerp(color, AppTokens.onAccent, towardWhite.clamp(0.0, 1.0))!;
    final hsl = HSLColor.fromColor(lightened);
    return hsl
        .withSaturation((hsl.saturation * saturation).clamp(0.0, 1.0))
        .toColor();
  }

  static FundCardPalette forCard({
    required bool isPacket,
    required bool settled,
    required bool dark,
    required bool highContrast,
  }) {
    // Query progress affects the status text, not the card's identity colors.
    // Entering an unread packet must not paint a white loading surface first.
    if (highContrast) {
      return FundCardPalette(
        body: AppTokens.surface(dark: dark),
        bodyHighlight: AppTokens.surface(dark: dark),
        footer: AppTokens.surfaceAlt(dark: dark),
        iconBg: AppTokens.surfaceAlt(dark: dark),
        icon: AppTokens.textPrimary(dark: dark),
        title: AppTokens.textPrimary(dark: dark),
        subtitle: AppTokens.textPrimary(dark: dark),
        meta: AppTokens.textPrimary(dark: dark),
        footerText: AppTokens.textPrimary(dark: dark),
      );
    }
    return isPacket ? (settled ? packet.opened() : packet) : transfer;
  }
}
