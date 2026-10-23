import 'package:flutter/painting.dart';
import 'package:openim_common/openim_common.dart';

/// Business color tokens with the 99chat opened-tone transformation.
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
    title: AppTokens.onAccent,
    subtitle: AppTokens.onAccent,
    meta: AppTokens.onAccent,
    footerText: AppTokens.onAccent,
  );
  static const luckyPacket = FundCardPalette(
    body: Color(0xFFE07A2E),
    bodyHighlight: Color(0xFFF2994A),
    footer: Color(0xFFD67127),
    iconBg: Color(0xFFFFF4E8),
    icon: Color(0xFFE07A2E),
    title: AppTokens.onAccent,
    subtitle: AppTokens.onAccent,
    meta: AppTokens.onAccent,
    footerText: AppTokens.onAccent,
  );

  static const exclusivePacket = FundCardPalette(
    body: Color(0xFFBE5963),
    bodyHighlight: Color(0xFFCD6870),
    footer: Color(0xFFB5535D),
    iconBg: Color(0xFFFFF2F1),
    icon: Color(0xFFBE5963),
    title: AppTokens.onAccent,
    subtitle: AppTokens.onAccent,
    meta: AppTokens.onAccent,
    footerText: AppTokens.onAccent,
  );

  static const transfer = FundCardPalette(
    body: Color(0xFFD47166),
    bodyHighlight: Color(0xFFD47166),
    footer: Color(0xFFC06258),
    iconBg: Color(0xFFFFF1EE),
    icon: Color(0xFFA85A52),
    title: AppTokens.onAccent,
    subtitle: AppTokens.onAccent,
    meta: AppTokens.onAccent,
    footerText: AppTokens.onAccent,
  );

  static const groupTransfer = FundCardPalette(
    body: Color(0xFF2FAE8F),
    bodyHighlight: Color(0xFF2FAE8F),
    footer: Color(0xFF1F8A72),
    iconBg: Color(0xFFEAF8F3),
    icon: Color(0xFF1F8A72),
    title: AppTokens.onAccent,
    subtitle: AppTokens.onAccent,
    meta: AppTokens.onAccent,
    footerText: AppTokens.onAccent,
  );

  FundCardPalette opened({bool referencePacket = false}) {
    final paleBody = _openedTone(body, towardWhite: .34, saturation: .72);
    final paleHighlight = _openedTone(bodyHighlight,
        towardWhite: referencePacket ? .40 : .34,
        saturation: referencePacket ? .76 : .72);
    final paleFooter = _openedTone(footer,
        towardWhite: referencePacket ? .30 : .34,
        saturation: referencePacket ? .70 : .72);
    return FundCardPalette(
      body: paleBody,
      bodyHighlight: paleHighlight,
      footer: paleFooter,
      iconBg: referencePacket
          ? _openedTone(iconBg, towardWhite: .22, saturation: .85)
          : iconBg,
      icon: icon,
      title: AppTokens.onAccent,
      subtitle: AppTokens.onAccent,
      meta: AppTokens.onAccent,
      footerText: AppTokens.onAccent,
    );
  }

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
    required String biz,
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
    final base = switch (biz) {
      'packet_lucky' => luckyPacket,
      'packet_exclusive' => exclusivePacket,
      'transfer' => transfer,
      'group_transfer' => groupTransfer,
      _ => packet,
    };
    return settled && biz.startsWith('packet_') && biz != 'packet_exclusive'
        ? base.opened(referencePacket: true)
        : base;
  }
}
